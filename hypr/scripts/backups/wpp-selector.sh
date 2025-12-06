#!/bin/bash

# Wallpaper selector script for Arch + Hyprland

WALLPAPER_DIR="/JP/Wallpapers"
MENU_THEME="/home/jon/.config/rofi/wallpaper-list.rasi"
SEARCH_THEME="/home/jon/.config/rofi/wallpaper-search.rasi"
HYPRPAPER_CONF="/home/jon/.config/hypr/hyprpaper.conf"
HYPRLOCK_CONF="/home/jon/.config/hypr/hyprlock.conf"

# Global cache variables
declare -a WALLPAPER_ARRAY
declare CURRENT_WALLPAPER_CACHE

# Initialize and validate
initialize_script() {
  if [ ! -d "$WALLPAPER_DIR" ]; then
    echo "Error: Wallpaper directory $WALLPAPER_DIR does not exist"
    exit 1
  fi

  if [ ! -f "$MENU_THEME" ]; then
    echo "Error: Rofi menu theme $MENU_THEME does not exist"
    exit 1
  fi

  if [ ! -f "$SEARCH_THEME" ]; then
    echo "Error: Rofi search theme $SEARCH_THEME does not exist"
    exit 1
  fi

  if [ ! -f "$HYPRPAPER_CONF" ]; then
    echo "Error: hyprpaper config $HYPRPAPER_CONF does not exist"
    exit 1
  fi

  if [ ! -f "$HYPRLOCK_CONF" ]; then
    echo "Error: hyprlock config $HYPRLOCK_CONF does not exist"
    exit 1
  fi

  # Load all wallpapers once at startup
  load_wallpapers_cache
}

load_wallpapers_cache() {
  echo "Loading wallpaper cache..."
  mapfile -t WALLPAPER_ARRAY < <(
    find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.bmp" -o -iname "*.gif" -o -iname "*.webp" \) -printf "%f\n" | sort
  )

  if [ ${#WALLPAPER_ARRAY[@]} -eq 0 ]; then
    echo "No wallpapers found in $WALLPAPER_DIR"
    exit 1
  fi

  echo "âœ“ Loaded ${#WALLPAPER_ARRAY[@]} wallpapers into cache"
}

get_wallpapers() {
  printf '%s\n' "${WALLPAPER_ARRAY[@]}"
}

get_current_wallpaper() {
  # Cache the current wallpaper to avoid repeated file parsing
  if [ -z "$CURRENT_WALLPAPER_CACHE" ]; then
    if [ -f "$HYPRPAPER_CONF" ]; then
      CURRENT_WALLPAPER_CACHE=$(grep -E '^wallpaper\s*=\s*DP-1,' "$HYPRPAPER_CONF" | head -1 | sed -E 's/^wallpaper\s*=\s*DP-1,\s*"?([^"]*)"?/\1/')
    fi
  fi
  echo "$CURRENT_WALLPAPER_CACHE"
}

get_random_wallpaper() {
  local count=${#WALLPAPER_ARRAY[@]}
  local current_wallpaper current_filename

  if [ $count -eq 0 ]; then
    echo ""
    return 1
  fi

  current_wallpaper=$(get_current_wallpaper)
  current_filename=$(basename "$current_wallpaper" 2>/dev/null)

  # If we have current wallpaper and multiple options, filter it out
  if [ -n "$current_filename" ] && [ $count -gt 1 ]; then
    local filtered_wallpapers=()
    for wp in "${WALLPAPER_ARRAY[@]}"; do
      if [ "$wp" != "$current_filename" ]; then
        filtered_wallpapers+=("$wp")
      fi
    done

    local filtered_count=${#filtered_wallpapers[@]}
    if [ $filtered_count -gt 0 ]; then
      local random_index=$((RANDOM % filtered_count))
      echo "${filtered_wallpapers[$random_index]}"
      return 0
    fi
  fi

  # Fallback to random from all wallpapers
  local random_index=$((RANDOM % count))
  echo "${WALLPAPER_ARRAY[$random_index]}"
}

display_wallpapers() {
  local theme="$1"
  if [ "$theme" = "$MENU_THEME" ]; then
    printf '%s\n' "${WALLPAPER_ARRAY[@]}" | rofi -dmenu -theme "$theme" -p "ï€¾" -kb-custom-1 "F1" -kb-custom-2 "r"
  else
    printf '%s\n' "${WALLPAPER_ARRAY[@]}" | rofi -dmenu -theme "$theme" -p "ï€¾" -kb-custom-1 "F1" -i
  fi
}

send_notification() {
  local wallpaper_file="$1"
  local display_name=$(basename "$wallpaper_file" | sed 's/\.[^.]*$//')

  if command -v dunstify &>/dev/null; then
    dunstify "New Wallpaper and Theme:" "$display_name" \
      -r 1000 \
      -t 3000
    echo "âœ“ Notification sent: $display_name"
  elif command -v notify-send &>/dev/null; then
    notify-send "New Wallpaper and Theme:" "$display_name" \
      -t 3000
    echo "âœ“ Notification sent (via notify-send): $display_name"
  else
    echo "âš  Notification not sent: dunstify/notify-send not available"
  fi
}

generate_pywal_scheme() {
  local wallpaper_path="$1"

  if ! command -v wal &>/dev/null; then
    echo "Warning: pywal (wal) is not installed. Skipping color scheme generation."
    return 1
  fi

  if [ ! -f "$wallpaper_path" ]; then
    echo "Error: Wallpaper file does not exist: $wallpaper_path"
    return 1
  fi

  echo "Generating color scheme with pywal..."

  if wal -i "$wallpaper_path" -n -s; then
    echo "âœ“ Pywal color scheme generated successfully"
    reload_pywal_apps
    return 0
  else
    echo "âœ— Failed to generate pywal color scheme"
    return 1
  fi
}

reload_pywal_apps() {
  echo "Reloading applications with new color scheme..."
  if pgrep dunst >/dev/null; then
    echo "  â†’ Removing all Dunst notifications..."
    killall dunst 2>/dev/null
  fi
  if pgrep waybar >/dev/null; then
    echo "  â†’ Restarting waybar..."
    killall waybar 2>/dev/null
    sleep 0.5
    waybar &
    echo "  â†’ Waybar restarted"
  else
    echo "  â†’ Waybar not running, skipping"
  fi
}

update_hyprpaper() {
  local wallpaper_path="$1"

  if [ ! -f "$wallpaper_path" ]; then
    echo "Error: Wallpaper file does not exist: $wallpaper_path"
    return 1
  fi

  if command -v hyprctl &>/dev/null; then
    echo "Setting wallpaper via hyprpaper IPC..."
    hyprctl hyprpaper preload "$wallpaper_path"
    hyprctl hyprpaper wallpaper "DP-1,$wallpaper_path"
    hyprctl hyprpaper unload all
    echo "âœ“ Hyprpaper wallpaper applied via IPC"
  else
    echo "Error: hyprctl not available"
    return 1
  fi
}

update_hyprlock() {
  local wallpaper_path="$1"

  if [[ ! -f "$HYPRLOCK_CONF" ]]; then
    echo "Warning: hyprlock config not found at $HYPRLOCK_CONF"
    return 1
  fi

  local escaped_path=$(echo "$wallpaper_path" | sed 's/\//\\\//g')
  sed -i '/^background {/,/^}/ s/\(^[[:space:]]*path = \).*$/\1'"$escaped_path"'/' "$HYPRLOCK_CONF"

  if [[ $? -eq 0 ]]; then
    echo "âœ“ Hyprlock background updated"
  else
    echo "âœ— Failed to update hyprlock configuration"
    return 1
  fi
}

update_hyprpaper_conf() {
  local wallpaper_file="$1"
  local wallpaper_path="$WALLPAPER_DIR/$wallpaper_file"
  local temp_conf=$(mktemp)

  while IFS= read -r line; do
    if [[ "$line" =~ ^preload\ *=\ * ]]; then
      if [[ "$line" =~ \".*\" ]]; then
        echo "preload = \"$wallpaper_path\"" >>"$temp_conf"
      else
        echo "preload = $wallpaper_path" >>"$temp_conf"
      fi
    elif [[ "$line" =~ ^wallpaper\ *=\ *DP-1, ]]; then
      if [[ "$line" =~ \".*\" ]]; then
        echo "wallpaper = DP-1,\"$wallpaper_path\"" >>"$temp_conf"
      else
        echo "wallpaper = DP-1,$wallpaper_path" >>"$temp_conf"
      fi
    else
      echo "$line" >>"$temp_conf"
    fi
  done <"$HYPRPAPER_CONF"

  mv "$temp_conf" "$HYPRPAPER_CONF"
  echo "âœ“ Hyprpaper.conf updated"
}

apply_wallpaper() {
  local selected="$1"
  local wallpaper_path="$WALLPAPER_DIR/$selected"

  echo "Selected: $selected"
  echo "Full path: $wallpaper_path"

  # Update current wallpaper cache
  CURRENT_WALLPAPER_CACHE="$wallpaper_path"

  generate_pywal_scheme "$wallpaper_path"
  update_hyprpaper_conf "$selected"
  update_hyprpaper "$wallpaper_path"
  update_hyprlock "$wallpaper_path"
  send_notification "$selected"

  echo "ðŸŽ‰ Wallpaper and color scheme applied successfully!"
}

main() {
  initialize_script

  if [[ "$1" == "-r" || "$1" == "--random" ]]; then
    random_wallpaper=$(get_random_wallpaper)
    if [ -n "$random_wallpaper" ]; then
      apply_wallpaper "$random_wallpaper"
    else
      echo "Error: No wallpapers found to select randomly"
      exit 1
    fi
  else
    current_theme="$MENU_THEME"
    selected=$(display_wallpapers "$current_theme")
    rofi_exit_code=$?

    while [ $rofi_exit_code -eq 10 ] || [ $rofi_exit_code -eq 11 ]; do
      if [ $rofi_exit_code -eq 10 ]; then
        if [ "$current_theme" = "$MENU_THEME" ]; then
          current_theme="$SEARCH_THEME"
        else
          current_theme="$MENU_THEME"
        fi
      elif [ $rofi_exit_code -eq 11 ]; then
        random_wallpaper=$(get_random_wallpaper)
        if [ -n "$random_wallpaper" ]; then
          apply_wallpaper "$random_wallpaper"
          exit 0
        else
          echo "Error: No wallpapers found to select randomly"
          exit 1
        fi
      fi

      selected=$(display_wallpapers "$current_theme")
      rofi_exit_code=$?
    done

    if [ -n "$selected" ]; then
      apply_wallpaper "$selected"
    else
      echo "No selection made"
    fi
  fi
}

# Run the main function
main "$@"
