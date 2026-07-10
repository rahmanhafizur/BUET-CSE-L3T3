#!/usr/bin/bash

BVCS_DIR=".bvcs"

do_init() {

    if [ -d "$BVCS_DIR" ]; then
        echo "Error: BVCS repository already exists."
        exit 1
    fi

    mkdir "$BVCS_DIR"
    mkdir "$BVCS_DIR/objects"

    touch "$BVCS_DIR/staging"
    touch "$BVCS_DIR/log"
    touch "$BVCS_DIR/HEAD"

    echo "Initialized empty BVCS repository."
}

require_repo() {
    if [ ! -d "$BVCS_DIR" ]; then
        echo "Error: Not a BVCS repository. Run 'init' first."
        exit 1
    fi
}

# ei file ei latest commit er id ta thake
current_head() {
    cat "$BVCS_DIR/HEAD"
}

add_files() {
    require_repo

    if [ "$#" -eq 0 ]; then             # $# diye koyta argument pass kora hoise ta check kora hoise
        echo "Error: No files specified."
        exit 1
    fi

    local file

    for file in "$@"                    # $@ shob file check kora hoise
    do                
        file=$(normalize_path "$file")      # eita path clean kore dey (./main.c → main.c)

        if [ ! -f "$file" ]; then
            echo "Error: '$file' not found."
            continue
        fi

        if is_staged "$file"; then
            echo "Already staged: $file"
            continue
        fi

        echo "$file" >> "$BVCS_DIR/staging"
        echo "Staged: $file"
    done
}

is_staged() {
    local file="$1"

    if grep -Fx "$file" "$BVCS_DIR/staging" > /dev/null 2>&1            # grep -Fx exact line match khoje ar > /dev/null 2>&1 output ke suppress kore
    then
        return 0        #file staged
    else
        return 1        #file not staged
    fi
}

has_commits() {
    [ -s "$BVCS_DIR/HEAD" ]
}


is_tracked() {
    local id
    id=$(current_head)

    [ -n "$id" ] && [ -f "$BVCS_DIR/objects/$id/files/$1" ]
}

normalize_path() {
    local file="$1"

    while [[ "$file" == ./* ]]; do
        file="${file#./}"
    done

    echo "$file"
}

show_status() {
    require_repo

    toCommitOrNotTracker=0

    id=$(current_head)
    snapshot="$BVCS_DIR/objects/$id/files"

    modified_file=$(mktemp)
    untracked_file=$(mktemp)

    # Staged files
    if [ -s "$BVCS_DIR/staging" ]; then
        echo "Staged for commit:"
        cat "$BVCS_DIR/staging"
        echo
        toCommitOrNotTracker=1
    fi

    # Modified files
    if [ -n "$id" ]; then
        find "$snapshot" -type f -printf '%P\n' | sort |
        while IFS= read -r file; do

            if is_staged "$file"; then
                continue
            fi

            if [ ! -f "$file" ]; then
                echo "$file" >> "$modified_file"
            elif ! cmp -s "$snapshot/$file" "$file"; then
                echo "$file" >> "$modified_file"
            fi
        done
    fi

    # Untracked files
    find . -path './.bvcs' -prune -o -type f -printf '%P\n' | sort |
    while IFS= read -r file; do

        if is_staged "$file"; then
            continue
        fi

        if ! is_tracked "$file"; then
            echo "$file" >> "$untracked_file"
        fi
    done

    # Print modified files
    if [ -s "$modified_file" ]; then
        echo "Modified (not staged):"
        cat "$modified_file"
        echo
        toCommitOrNotTracker=1
    fi

    # Print untracked files
    if [ -s "$untracked_file" ]; then
        echo "Untracked files:"
        cat "$untracked_file"
        echo
        toCommitOrNotTracker=1
    fi

    rm -f "$modified_file"
    rm -f "$untracked_file"

    if [ "$toCommitOrNotTracker" -eq 0 ]; then
        echo "Nothing to commit, working tree clean."
    fi
}

next_commit_id() {
    local count

    count=$(wc -l < "$BVCS_DIR/log")
    printf "%04d" $((count + 1))
}

do_commit() {
    require_repo

    # Checking commit message
    if [ "$1" != "-m" ]; then
        echo "Error: Commit message required. Use -m \"message\"."
        exit 1
    fi

    if [ -z "$2" ]; then
        echo "Error: Commit message required. Use -m \"message\"."
        exit 1
    fi

    # Checking staging area
    if [ ! -s "$BVCS_DIR/staging" ]; then
        echo "Error: Nothing to commit."
        exit 1
    fi

    message="$2"

    old_id=$(current_head)
    new_id=$(next_commit_id)

    new_folder="$BVCS_DIR/objects/$new_id"
    old_folder="$BVCS_DIR/objects/$old_id/files"

    mkdir -p "$new_folder/files"

    # Copy previous snapshot
    if [ -n "$old_id" ]; then
        if [ -d "$old_folder" ]; then
            cp -r "$old_folder/." "$new_folder/files/"
        fi
    fi

    count=0

    # Copy staged files
    while IFS= read -r file; do
        folder=$(dirname "$file")

        mkdir -p "$new_folder/files/$folder"
        cp "$file" "$new_folder/files/$file"

        count=$((count + 1))
    done < "$BVCS_DIR/staging"

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Save commit information
    echo "$message" > "$new_folder/message"
    echo "$timestamp" > "$new_folder/timestamp"

    echo "$new_id|$timestamp|$message" >> "$BVCS_DIR/log"
    echo "$new_id" > "$BVCS_DIR/HEAD"

    # Clear staging area; permanently delete kortesi na... shudhu vetorer lekha clear kortesi
    echo -n "" > "$BVCS_DIR/staging"

    echo "[$new_id] $message"
    echo "$count file(s) committed."
}

show_log() {
    require_repo

    if [ ! -s "$BVCS_DIR/log" ]; then
        echo "No commits yet."
        exit 0
    fi

    local id
    local timestamp
    local message

    tac "$BVCS_DIR/log" |
    while IFS='|' read -r id timestamp message; do
        echo "commit $id"
        echo "Date: $timestamp"
        echo "Message: $message"
        echo
    done
}

diff_one_file() {
    file="$1"
    id=$(current_head)

    snapshot="$BVCS_DIR/objects/$id/files/$file"

    if [ ! -f "$snapshot" ]; then
        echo "Error: '$file' is not tracked."
        return
    fi

    if [ ! -f "$file" ]; then
        diff -u \
            --label "$snapshot" \
            --label "$file" \
            "$snapshot" /dev/null
        return
    fi

    if cmp -s "$snapshot" "$file"; then
        echo "$file: no changes."
    else
        diff -u \
            --label "$snapshot" \
            --label "$file" \
            "$snapshot" "$file"
    fi
}

show_diff() {
    require_repo

    if ! has_commits; then
        echo "Error: No commits yet."
        exit 1
    fi

    local id
    local snapshot
    local file

    id=$(current_head)
    snapshot="$BVCS_DIR/objects/$id/files"

    if [ "$#" -gt 0 ]; then
        file=$(normalize_path "$1")
        diff_one_file "$file"
    else
        while IFS= read -r file; do
            diff_one_file "$file"
        done < <(find "$snapshot" -type f -printf '%P\n' | sort)
    fi
}

restore_file() {
    require_repo

    if [ "$#" -eq 0 ]; then
        echo "Error: No file specified."
        exit 1
    fi

    if ! has_commits; then
        echo "Error: No commits yet."
        exit 1
    fi

    local file
    local id
    local snap_path
    local answer

    file=$(normalize_path "$1")
    id=$(current_head)
    snap_path="$BVCS_DIR/objects/$id/files/$file"

    if [ ! -f "$snap_path" ]; then
        echo "Error: '$file' not found in commit $id."
        exit 1
    fi

    printf "Restore '%s' from commit %s? [y/N]: " "$file" "$id"
    read -r answer

    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        mkdir -p "$(dirname "$file")"
        cp "$snap_path" "$file"

        echo "Restored: $file"
    else
        echo "Aborted."
        exit 0
    fi
}

cmd_help() {
    echo "Usage: bvcs <subcommand> [options]"
    echo
    echo "Subcommands:"
    echo "  init"
    echo "  add <file> [file ...]"
    echo "  status"
    echo "  commit -m \"message\""
    echo "  log"
    echo "  diff [file]"
    echo "  restore <file>"
    echo "  help"
}

subcommand="$1"
shift 2>/dev/null || true

case "$subcommand" in
    init)
        do_init "$@"
        ;;

    add)
        add_files "$@"
        ;;

    status)
        show_status "$@"
        ;;

    commit)
        do_commit "$@"
        ;;

    log)
        show_log "$@"
        ;;

    diff)
        show_diff "$@"
        ;;

    restore)
        restore_file "$@"
        ;;

    help|"")
        cmd_help
        ;;

    *)
        echo "Error: Unknown subcommand '$subcommand'."
        exit 1
        ;;
esac
