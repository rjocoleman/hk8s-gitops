# Edit encrypted file with SOPS
edit file:
    op run -- sops {{file}}

# Encrypt file in place
encrypt file:
    op run -- sops --encrypt --encrypted-regex '^(data|stringData)$' --in-place {{file}}

# Decrypt file (use carefully)
decrypt file:
   op run -- sops --decrypt --in-place {{file}}

# Check for unencrypted secrets in staged files
check *FILES:
    #!/usr/bin/env bash
    set -euo pipefail
    IFS=$'\n\t'

    # Filter YAML files from the passed arguments
    yaml_files=$(echo "{{ FILES }}" | tr ' ' '\n' | grep -E '\.(yaml|yml)$' || true)

    # Check each file for unencrypted secrets
    unencrypted_files=""
    for file in $yaml_files; do
        if grep -q '^kind: Secret' "$file" && ! grep -q 'sops:' "$file"; then
            unencrypted_files+="$file"$'\n'
        fi
    done

    if [ -n "$unencrypted_files" ]; then
        echo "The following files contain unencrypted or improperly encrypted secrets:"
        echo "$unencrypted_files"
        echo "Please use SOPS to encrypt these files before committing."
        exit 1
    fi

    echo "All secret manifests are properly encrypted."
    exit 0

# Install git hooks
add-githooks:
    git config core.hooksPath .githooks

# Generate kubeconfig from template
kubeconfig:
    envsubst < kubeconfig.tmpl.yaml > kubeconfig.yaml

# Generate talosconfig from template
talosconfig:
    envsubst < talosconfig.tmpl.yaml > talosconfig.yaml

# Generate omniconfig from template
omniconfig:
    envsubst < omniconfig.tmpl.yaml > omniconfig.yaml

# Generate all configs
configs: kubeconfig talosconfig omniconfig
    @echo "All configs generated"

# Clean generated configs
clean-configs:
    rm -f kubeconfig.yaml talosconfig.yaml omniconfig.yaml
