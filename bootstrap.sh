#!/usr/bin/env bash
# Run once per instance session, right after SSH-ing in and cloning this repo:
#
#   source bootstrap.sh <project-name>
#
# Must be *sourced*, not executed, so the venv activation and exported env
# vars persist in your interactive shell.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: run this with 'source bootstrap.sh <project-name>', not './bootstrap.sh ...'" >&2
    exit 1
fi

_bootstrap() {
    local project="$1"
    if [[ -z "$project" ]]; then
        echo "usage: source bootstrap.sh <project-name>" >&2
        return 1
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local req_file="$script_dir/projects/$project/requirements-extra.txt"
    local apt_file="$script_dir/projects/$project/apt-extra.txt"

    if [[ ! -d "$script_dir/projects/$project" ]]; then
        echo "ERROR: no projects/$project directory in this repo." >&2
        return 1
    fi

    local fs_name="${LAMBDA_FS_NAME:-ml-persist}"
    local fs_root="/lambda/nfs/$fs_name"

    if [[ ! -d "$fs_root" ]]; then
        echo "ERROR: filesystem not mounted at $fs_root." >&2
        echo "Did you attach filesystem '$fs_name' when launching this instance?" >&2
        echo "(Set LAMBDA_FS_NAME before sourcing this script if your filesystem has a different name.)" >&2
        return 1
    fi

    local venv_dir="$fs_root/envs/$project"
    local hf_cache="$fs_root/hf-cache"
    local checkpoint_dir="$fs_root/projects/$project/checkpoints"
    local dataset_dir="$fs_root/projects/$project/datasets"
    local ssh_dir="$fs_root/ssh"
    local gh_key="$ssh_dir/github_deploy_key"

    mkdir -p "$hf_cache" "$checkpoint_dir" "$dataset_dir"

    if [[ -f "$gh_key" ]]; then
        chmod 600 "$gh_key"
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        if ! grep -q "^Host github.com$" "$HOME/.ssh/config" 2>/dev/null; then
            {
                echo ""
                echo "Host github.com"
                echo "    IdentityFile $gh_key"
                echo "    IdentitiesOnly yes"
            } >> "$HOME/.ssh/config"
            chmod 600 "$HOME/.ssh/config"
        fi
        if ! ssh-keygen -F github.com >/dev/null 2>&1; then
            ssh-keyscan -H github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
        fi
        echo "GitHub SSH key wired up from $gh_key"
    else
        echo "NOTE: no GitHub deploy key found at $gh_key"
        echo "  One-time step: from your Mac, scp your private key up, e.g.:"
        echo "    scp -i id_ed25519 <path-to-private-key> ubuntu@<instance-ip>:$gh_key"
        echo "  Then re-run: source bootstrap.sh $project"
    fi

    if [[ -f "$apt_file" ]]; then
        local apt_updated=0
        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" == \#* ]] && continue
            if ! dpkg -s "$pkg" >/dev/null 2>&1; then
                if [[ "$apt_updated" -eq 0 ]]; then
                    sudo apt-get update -qq
                    apt_updated=1
                fi
                echo "Installing system package: $pkg"
                sudo apt-get install -y "$pkg"
            fi
        done < "$apt_file"
    fi

    if [[ ! -d "$venv_dir" ]]; then
        echo "First run for '$project' — creating venv on persistent storage (inherits Lambda Stack packages)..."
        python3 -m venv --system-site-packages "$venv_dir"
        source "$venv_dir/bin/activate"
        pip install --upgrade pip >/dev/null
        if [[ -f "$req_file" ]]; then
            pip install -r "$req_file"
        fi
        local setup_extra="$script_dir/projects/$project/setup-extra.sh"
        if [[ -f "$setup_extra" ]]; then
            echo "Running setup-extra.sh for $project..."
            bash "$setup_extra" "$venv_dir"
        fi
        python3 -V > "$venv_dir/.bootstrap-python-version"
    else
        source "$venv_dir/bin/activate"
        local recorded current
        recorded="$(cat "$venv_dir/.bootstrap-python-version" 2>/dev/null || echo unknown)"
        current="$(python3 -V)"
        if [[ "$recorded" != "$current" ]]; then
            echo "WARNING: this instance's Python ($current) differs from when the venv" >&2
            echo "was created ($recorded). Lambda Stack images may have changed between" >&2
            echo "dev/test and prod instances. If imports fail, remove and rebuild:" >&2
            echo "  rm -rf $venv_dir && source bootstrap.sh $project" >&2
        fi
        echo "Existing venv for '$project' found — activated, no reinstall needed."
    fi

    export HF_HOME="$hf_cache"
    export HUGGINGFACE_HUB_CACHE="$hf_cache/hub"
    export ML_CHECKPOINT_DIR="$checkpoint_dir"
    export ML_DATASET_DIR="$dataset_dir"

    echo ""
    echo "Ready. venv active: $VIRTUAL_ENV"
    echo "HF_HOME             -> $HF_HOME"
    echo "ML_CHECKPOINT_DIR    -> $ML_CHECKPOINT_DIR"
    echo "ML_DATASET_DIR       -> $ML_DATASET_DIR"
}

_bootstrap "$1"
unset -f _bootstrap
