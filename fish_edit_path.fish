# Author: tonakihan
# Dependencies: fzf
# 
# Description: This function add a TUI mode to edit $fish_user_paths using fzf

function fish_edit_path
  set -l selected_path
  set -l list_actions "add" "delete" "edit" "move" "_quit_"
  
  set -l action (
    printf "%s\n" $list_actions |
    fzf \
      --preview-label "Current value of \$fish_user_paths" \
      --preview 'printf "%s\n" $fish_user_paths | nl' \
      --header "Set action"
  )

  if test -z "$action"
    echo "Cancelled"
    return 0
  end

  if ! string match -qr "^(add|_quit_)\$" $action
    set selected_path (
      printf "%s\n" $fish_user_paths |
      tac |
      fzf --header "Select a path to modify"
    )

    if test -z "$selected_path"
      echo "Cancelled"
      return 0
    end
  end

  switch $action
    case add
      __add_path
    case delete
      __delete_path $selected_path
    case edit
      __edit_path $selected_path
    case move
      __move_path $selected_path
    case _quit_
      return 0
  end
end


function __add_path
  set -l new_path (
    fzf \
      --walker=dir,hidden \
      --walker-root=/ \
      --header="Set a new path"
  )

  if test -z "$new_path"
    echo "Cancelled"
    return 0
  end

  set -l updated_paths $new_path $fish_user_paths

  # Apply changes
  __confirm __show_diff_path $updated_paths || return 0

  set -U fish_user_paths $updated_paths
  echo "Added"
end


function __delete_path
  set -l target_path $argv
  set -l updated_paths (string match -v $target_path $fish_user_paths)
  
  # Apply changes
  __confirm __show_diff_path $updated_paths || return 0

  set -U fish_user_paths $updated_paths
  echo "Deleted"
end


function __edit_path
  set -l old_path $argv

  set -l new_path (
    fzf \
      --walker=dir,hidden \
      --walker-root=/ \
      -q $old_path \
      --header="Set a new destonation"
  )

  if test -z "$new_path"
    echo "Cancelled"
    return 0
  end

  set -l updated_paths (
    string replace -r "^$old_path\$" $new_path $fish_user_paths
  )
  
  # Apply changes
  __confirm __show_diff_path $updated_paths || return 0

  set -U fish_user_paths $updated_paths
  echo "Updated"
end


function __move_path
  set -l target_path $argv
 
  set -l old_index (contains -i -- $target_path $fish_user_paths)

  set -l total_elements (count $fish_user_paths)

  set -l new_index (
    seq $total_elements | 
    tac |
    fzf \
      --header "Select new position for: $target_path" \
      --preview-label "Preview of new order" \
      --preview "
        set -l idx {}
        set -l paths $fish_user_paths
        set -l target $target_path
  
        set -e paths[$old_index]

        # Insert the path to a new position
        if test \$idx -eq 1
          set paths '$target_path' \$paths
        else if test \$idx -gt (count \$paths)
          set paths \$paths '$target_path'
        else
          set paths \$paths[1..(math \$idx - 1)] '$target_path' \$paths[\$idx..-1]
        end
  
        # Print the changed order
        for i in (seq 1 (count \$paths))
          if test \"\$paths[\$i]\" = '$target_path'
            printf '\e[1;32m%2d: %s (MOVED)\e[0m\n' \$i \$paths[\$i]
          else
            printf '%2d: %s\n' \$i \$paths[\$i]
          end
        end
      "
  )

  if test -z "$new_index"
      echo "Cancelled"
      return 0
  end

  # If haven't changes
  if test "$old_index" -eq "$new_index"
      echo "Position unchanged"
      return 0
  end

  # Modify the path 
  set -l updated_paths $fish_user_paths
  set -e updated_paths[$old_index]
  #
  if test "$new_index" -eq 1
      set updated_paths $target_path $updated_paths
  else if test "$new_index" -gt (count $updated_paths)
      set updated_paths $updated_paths $target_path
  else
      set updated_paths $updated_paths[1..(math $new_index - 1)] $target_path $updated_paths[$new_index..-1]
  end

  # Apply changes
  __confirm __show_diff_path $updated_paths || return 0

  set -U fish_user_paths $updated_paths
  echo "Moved"
end


# =============== UTILS ================

function __show_diff
  argparse "str1=" "str2=" -- $argv 
    or return 1

  #echo "[DBG]: __show_diff: argv=$argv"
  #echo "[DBG]: __show_diff: count=$(count $argv)"
  #echo "[DBG]: __show_diff: str1=$_flag_str1"
  #echo "[DBG]: __show_diff: str2=$_flag_str2"

  set -l tmp_old (mktemp)
  set -l tmp_new (mktemp)
  string split ":" $_flag_str1 > $tmp_old
  string split ":" $_flag_str2 > $tmp_new

  # Print result
  diff -u $tmp_old $tmp_new | tail -n +3

  rm -f $tmp_old $tmp_new
end


function __show_diff_path
  argparse --min-args=1 -- $argv 
    or return 1

  __show_diff -str1=(string join ':' $fish_user_paths) -str2=(string join ':' $argv)
end


# The function can be called ONLY with executable command:
#   __confirm "echo message"
#   __confirm __show_diff_path $updated_path
function __confirm
  argparse --min-args=1 -- $argv 
    or return 1
  set -l cmd_preview $argv

  set -l tmp_preview (mktemp)
  $cmd_preview > $tmp_preview
  
  set -l answer (
    printf "%s\n" Apply Cancel |
    fzf \
      --preview "bat $tmp_preview" \
      --preview-label "Preview of the changes (diff)" \
      --header "Apply the changes?" 
  )
  
  rm -f $tmp_preview

  if ! string match -q "Apply" $answer
    echo "Cancelled"
    return 1
  end
  return 0
end

