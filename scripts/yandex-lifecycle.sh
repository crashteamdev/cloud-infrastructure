#!/usr/bin/env bash

set -euo pipefail

readonly TF_DIR="${TF_DIR:-yandex}"
readonly STATE_BUCKET="${STATE_BUCKET:-marketdb-tf-state}"
readonly GITHUB_DEPLOY_SERVICE_ACCOUNT_ID="ajevao7t27aim25olhi1"

readonly RECOVERY_ADDRESSES=(
  "yandex_iam_service_account.marketdb-tf"
  "yandex_resourcemanager_folder_iam_member.editor"
  "yandex_resourcemanager_folder_iam_member.github_deploy_storage_admin"
  "yandex_resourcemanager_folder_iam_member.k8s-clusters-agent"
  "yandex_resourcemanager_folder_iam_member.vpc-public-admin"
  "yandex_resourcemanager_folder_iam_member.images-puller"
)

readonly INVENTORY_COMMANDS=(
  "iam service-account"
  "managed-kubernetes cluster"
  "managed-postgresql cluster"
  "managed-redis cluster"
  "managed-clickhouse cluster"
  "managed-mongodb cluster"
  "managed-mysql cluster"
  "managed-kafka cluster"
  "managed-greenplum cluster"
  "compute instance-group"
  "compute instance"
  "compute disk"
  "compute snapshot"
  "compute filesystem"
  "vpc network"
  "vpc subnet"
  "vpc security-group"
  "vpc route-table"
  "vpc gateway"
  "vpc address"
  "load-balancer network-load-balancer"
  "load-balancer target-group"
  "application-load-balancer load-balancer"
  "application-load-balancer backend-group"
  "application-load-balancer http-router"
  "application-load-balancer target-group"
  "dns zone"
  "cdn resource"
  "cdn origin-group"
  "certificate-manager certificate"
  "kms symmetric-key"
  "container registry"
  "storage bucket"
  "serverless trigger"
  "serverless api-gateway"
  "serverless function"
  "serverless container"
  "serverless mdbproxy"
  "datatransfer transfer"
  "datatransfer endpoint"
  "lockbox secret"
  "logging group"
)

is_recovery_address() {
  local candidate="$1"
  local recovery

  for recovery in "${RECOVERY_ADDRESSES[@]}"; do
    if [[ "$candidate" == "$recovery" ]]; then
      return 0
    fi
  done

  return 1
}

is_storage_address() {
  local candidate="$1"

  case "$candidate" in
    yandex_storage_bucket.* \
      | yandex_iam_service_account.endmake_storage \
      | yandex_iam_service_account_static_access_key.endmake_storage \
      | yandex_resourcemanager_folder_iam_member.endmake_storage_admin \
      | yandex_resourcemanager_folder_iam_member.endmake_storage_editor)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

terraform_targets() {
  local mode="${1:-all}"
  local address

  while IFS= read -r address; do
    [[ -z "$address" ]] && continue
    is_recovery_address "$address" && continue

    case "$mode" in
      all)
        ;;
      core)
        is_storage_address "$address" && continue
        ;;
      storage)
        is_storage_address "$address" || continue
        ;;
      *)
        echo "Unknown target mode: $mode" >&2
        return 2
        ;;
    esac

    printf '%s\n' "-target=$address"
  done < <(terraform -chdir="$TF_DIR" state list)
}

backend_service_account_id() {
  local service_accounts service_account_id keys owner_id

  service_accounts="$(yc iam service-account list --format json)"
  while IFS= read -r service_account_id; do
    if ! keys="$(
      yc iam access-key list --service-account-id "$service_account_id" --format json 2>/dev/null
    )"; then
      continue
    fi
    owner_id="$(
      jq -r --arg access_key "$AWS_ACCESS_KEY_ID" \
        '.[] | select(.key_id == $access_key) | .service_account_id' <<< "$keys"
    )"
    if [[ -n "$owner_id" ]]; then
      printf '%s\n' "$owner_id"
      return 0
    fi
  done < <(jq -r '.[].id' <<< "$service_accounts")

  return 1
}

state_resource_value() {
  local address="$1"
  local attribute="$2"

  terraform -chdir="$TF_DIR" show -json \
    | jq -r --arg address "$address" --arg attribute "$attribute" '
        def resources:
          .resources[]?,
          (.child_modules[]? | resources);

        [
          .values.root_module
          | resources
          | select(.address == $address)
          | .values[$attribute]
        ][0] // empty
      '
}

state_resource_id() {
  state_resource_value "$1" id
}

assert_recovery_principal() {
  local auth_service_account_id backend_service_account_id_value
  local recovery_service_account_id address candidate_id

  auth_service_account_id="$(jq -r '.service_account_id // empty' "$YC_SERVICE_ACCOUNT_KEY_FILE")"
  if [[ -z "$auth_service_account_id" ]]; then
    echo "YC_SERVICE_ACCOUNT_KEY_FILE does not contain service_account_id" >&2
    return 1
  fi

  recovery_service_account_id="$(state_resource_id 'yandex_iam_service_account.marketdb-tf')"

  if [[ -z "$recovery_service_account_id" ]]; then
    echo "Unable to resolve the recovery Terraform service account from state" >&2
    return 1
  fi

  if ! backend_service_account_id_value="$(backend_service_account_id)"; then
    echo "Unable to resolve the Object Storage backend key owner" >&2
    return 1
  fi

  while IFS= read -r address; do
    [[ "$address" == "yandex_iam_service_account.marketdb-tf" ]] && continue
    candidate_id="$(state_resource_id "$address")"
    if [[ -n "$candidate_id" \
      && ( "$candidate_id" == "$auth_service_account_id" \
        || "$candidate_id" == "$backend_service_account_id_value" ) ]]; then
      echo "$address owns a workflow credential but is scheduled for deletion" >&2
      return 1
    fi
  done < <(terraform -chdir="$TF_DIR" state list | grep '^yandex_iam_service_account\.' || true)

  printf 'Workflow service account: %s\n' "$auth_service_account_id"
  printf 'Backend service account: %s\n' "$backend_service_account_id_value"
  printf 'Terraform recovery service account: %s\n' "$recovery_service_account_id"
}

list_json() {
  local specification="$1"
  local -a command_parts
  local result

  read -r -a command_parts <<< "$specification"
  if ! result="$(yc "${command_parts[@]}" list --format json 2>/dev/null)"; then
    printf 'UNAVAILABLE  %s\n' "$specification"
    return 0
  fi

  printf '%-12s %s\n' "$(jq 'length' <<< "$result")" "$specification"
}

inventory() {
  local specification

  echo "Yandex Cloud inventory:"
  for specification in "${INVENTORY_COMMANDS[@]}"; do
    list_json "$specification"
  done
}

delete_all() {
  local specification="$1"
  local -a command_parts
  local ids id

  read -r -a command_parts <<< "$specification"
  if ! ids="$(yc "${command_parts[@]}" list --format json 2>/dev/null | jq -r '.[].id')"; then
    echo "Unable to inspect $specification; leaving it for the final audit" >&2
    return 0
  fi

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "Deleting residual $specification $id"
    if ! yc "${command_parts[@]}" delete --id "$id"; then
      echo "Unable to delete $specification $id; continuing the emergency sweep" >&2
    fi
  done <<< "$ids"
}

delete_all_positional() {
  local specification="$1"
  local -a command_parts
  local ids id

  read -r -a command_parts <<< "$specification"
  if ! ids="$(yc "${command_parts[@]}" list --format json 2>/dev/null | jq -r '.[].id')"; then
    echo "Unable to inspect $specification; leaving it for the final audit" >&2
    return 0
  fi

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "Deleting residual $specification $id"
    if ! yc "${command_parts[@]}" delete "$id"; then
      echo "Unable to delete $specification $id; continuing the emergency sweep" >&2
    fi
  done <<< "$ids"
}

delete_all_protected() {
  local specification="$1"
  local -a command_parts
  local ids id

  read -r -a command_parts <<< "$specification"
  if ! ids="$(yc "${command_parts[@]}" list --format json 2>/dev/null | jq -r '.[].id')"; then
    echo "Unable to inspect $specification; leaving it for the final audit" >&2
    return 0
  fi

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "Disabling deletion protection for $specification $id"
    if ! yc "${command_parts[@]}" update --id "$id" --no-deletion-protection; then
      echo "Unable to disable deletion protection for $specification $id" >&2
    fi
    echo "Deleting residual $specification $id"
    if ! yc "${command_parts[@]}" delete --id "$id"; then
      echo "Unable to delete $specification $id; continuing the emergency sweep" >&2
    fi
  done <<< "$ids"
}

delete_protected_clusters() {
  local specification="$1"
  local -a command_parts
  local ids id

  read -r -a command_parts <<< "$specification"
  if ! ids="$(yc "${command_parts[@]}" list --format json 2>/dev/null | jq -r '.[].id')"; then
    echo "Unable to inspect $specification" >&2
    return 0
  fi

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "Disabling deletion protection for $specification $id"
    if ! yc "${command_parts[@]}" update --id "$id" --no-deletion-protection; then
      echo "Unable to disable deletion protection for $specification $id" >&2
    fi
    echo "Deleting $specification $id"
    if ! yc "${command_parts[@]}" delete --id "$id"; then
      echo "Unable to delete $specification $id; continuing the emergency sweep" >&2
    fi
  done <<< "$ids"
}

cleanup_kubernetes_residuals() {
  # Kubernetes controllers normally delete these resources with their Services
  # and PVCs. This sweep handles leftovers after the cluster is gone.
  delete_all "application-load-balancer load-balancer"
  delete_all "load-balancer network-load-balancer"
  delete_all "application-load-balancer http-router"
  delete_all "application-load-balancer backend-group"
  delete_all "application-load-balancer target-group"
  delete_all "load-balancer target-group"
  delete_all "compute instance-group"
  delete_all "compute instance"
  delete_all "compute filesystem"
  delete_all "compute disk"
  delete_all "vpc address"
}

cleanup_known_residuals() {
  # Delete consumers before their backing resources. Every operation is best
  # effort so one stale dependency cannot prevent deletion of billable items.
  delete_all_positional "datatransfer transfer"
  delete_all "serverless trigger"
  delete_all "cdn resource"
  delete_all "application-load-balancer load-balancer"
  delete_all "load-balancer network-load-balancer"
  delete_all "managed-kubernetes cluster"
  delete_protected_clusters "managed-postgresql cluster"
  delete_protected_clusters "managed-redis cluster"
  delete_protected_clusters "managed-clickhouse cluster"
  delete_protected_clusters "managed-mongodb cluster"
  delete_protected_clusters "managed-mysql cluster"
  delete_protected_clusters "managed-kafka cluster"
  delete_protected_clusters "managed-greenplum cluster"
  delete_all "compute instance-group"
  delete_all "compute instance"
  delete_all "compute filesystem"
  delete_all "compute disk"
  delete_all "compute snapshot"
  delete_all_positional "datatransfer endpoint"
  delete_all_protected "lockbox secret"
  delete_all "application-load-balancer http-router"
  delete_all "application-load-balancer backend-group"
  delete_all "application-load-balancer target-group"
  delete_all "load-balancer target-group"
  delete_all "cdn origin-group"
  delete_all_protected "certificate-manager certificate"
  delete_all "serverless api-gateway"
  delete_all "serverless function"
  delete_all "serverless container"
  delete_all "serverless mdbproxy"
  delete_all "container registry"
  delete_all "kms symmetric-key"
  delete_all "logging group"
  delete_all "dns zone"
  delete_all "vpc address"
  delete_all "vpc security-group"
  delete_all "vpc route-table"
  delete_all "vpc subnet"
  delete_all "vpc gateway"
  delete_all "vpc network"

  # Auto-created DNS zones can disappear only after their network is deleted.
  delete_all "dns zone"

  # CDN and Data Transfer deletion can release these dependencies with a delay.
  delete_all_protected "certificate-manager certificate"
  delete_all_protected "lockbox secret"
}

purge_bucket_with_credentials() {
  local bucket="$1"
  local bucket_access_key="$2"
  local bucket_secret_key="$3"
  local endpoint="https://storage.yandexcloud.net"
  local versions delete_payload uploads encoded key upload_id

  if ! AWS_ACCESS_KEY_ID="$bucket_access_key" AWS_SECRET_ACCESS_KEY="$bucket_secret_key" \
    aws --endpoint-url "$endpoint" --region ru-central1 \
      s3api head-bucket --bucket "$bucket"; then
    return 1
  fi

  AWS_ACCESS_KEY_ID="$bucket_access_key" AWS_SECRET_ACCESS_KEY="$bucket_secret_key" \
    aws --endpoint-url "$endpoint" --region ru-central1 \
      s3 rm "s3://$bucket" --recursive || return 1

  while true; do
    versions="$(
      AWS_ACCESS_KEY_ID="$bucket_access_key" AWS_SECRET_ACCESS_KEY="$bucket_secret_key" \
        aws --endpoint-url "$endpoint" --region ru-central1 \
          s3api list-object-versions --bucket "$bucket"
    )" || return 1
    delete_payload="$(
      jq -c '{
        Objects: ([.Versions[]?, .DeleteMarkers[]?] | map({Key, VersionId})),
        Quiet: true
      }' <<< "$versions"
    )"
    if [[ "$(jq '.Objects | length' <<< "$delete_payload")" -eq 0 ]]; then
      break
    fi
    AWS_ACCESS_KEY_ID="$bucket_access_key" AWS_SECRET_ACCESS_KEY="$bucket_secret_key" \
      aws --endpoint-url "$endpoint" --region ru-central1 \
        s3api delete-objects --bucket "$bucket" --delete "$delete_payload" \
        >/dev/null || return 1
  done

  uploads="$(
    AWS_ACCESS_KEY_ID="$bucket_access_key" AWS_SECRET_ACCESS_KEY="$bucket_secret_key" \
      aws --endpoint-url "$endpoint" --region ru-central1 \
        s3api list-multipart-uploads --bucket "$bucket"
  )" || return 1
  while IFS= read -r encoded; do
    [[ -z "$encoded" ]] && continue
    key="$(base64 --decode <<< "$encoded" | jq -r '.Key')"
    upload_id="$(base64 --decode <<< "$encoded" | jq -r '.UploadId')"
    AWS_ACCESS_KEY_ID="$bucket_access_key" AWS_SECRET_ACCESS_KEY="$bucket_secret_key" \
      aws --endpoint-url "$endpoint" --region ru-central1 \
        s3api abort-multipart-upload \
          --bucket "$bucket" --key "$key" --upload-id "$upload_id" || return 1
  done < <(jq -r '.Uploads[]? | @base64' <<< "$uploads")

  AWS_ACCESS_KEY_ID="$bucket_access_key" AWS_SECRET_ACCESS_KEY="$bucket_secret_key" \
    aws --endpoint-url "$endpoint" --region ru-central1 \
      s3api delete-bucket --bucket "$bucket"
}

purge_bucket_with_temporary_key() {
  local bucket="$1"
  local key_json key_resource_id bucket_access_key bucket_secret_key
  local attempt status=1

  if ! key_json="$(
    yc iam access-key create \
      --service-account-id "$GITHUB_DEPLOY_SERVICE_ACCOUNT_ID" \
      --description "Temporary lifecycle cleanup key" \
      --format json
  )"; then
    echo "Unable to create a temporary Object Storage access key" >&2
    return 1
  fi
  key_resource_id="$(jq -r '.access_key.id // .id // empty' <<< "$key_json")"
  bucket_access_key="$(jq -r '.access_key.key_id // .key_id // empty' <<< "$key_json")"
  bucket_secret_key="$(jq -r '.secret // empty' <<< "$key_json")"

  if [[ -n "$key_resource_id" \
    && -n "$bucket_access_key" \
    && -n "$bucket_secret_key" ]]; then
    for attempt in 1 2 3 4 5 6; do
      echo "Purging $bucket with a temporary recovery key (attempt $attempt/6)"
      if purge_bucket_with_credentials \
        "$bucket" "$bucket_access_key" "$bucket_secret_key"; then
        status=0
        break
      fi
      sleep 5
    done
  else
    echo "Unable to read temporary Object Storage credentials" >&2
  fi

  if [[ -n "$key_resource_id" ]]; then
    yc iam access-key delete --id "$key_resource_id" >/dev/null 2>&1 || true
  fi

  return "$status"
}

purge_bucket() {
  local bucket="$1"
  local bucket_access_key bucket_secret_key

  if [[ "$bucket" == "$STATE_BUCKET" ]]; then
    echo "Refusing to purge the Terraform state bucket" >&2
    return 1
  fi

  if ! yc storage bucket get "$bucket" >/dev/null 2>&1; then
    echo "Bucket $bucket is already absent"
    return 0
  fi

  bucket_access_key="$(
    state_resource_value \
      'yandex_iam_service_account_static_access_key.endmake_storage' access_key
  )"
  bucket_secret_key="$(
    state_resource_value \
      'yandex_iam_service_account_static_access_key.endmake_storage' secret_key
  )"
  if [[ -n "$bucket_access_key" && -n "$bucket_secret_key" ]]; then
    if purge_bucket_with_credentials \
      "$bucket" "$bucket_access_key" "$bucket_secret_key"; then
      return 0
    fi
    echo "The Terraform-managed bucket key is unavailable; using a temporary account" >&2
  fi

  purge_bucket_with_temporary_key "$bucket"
}

assert_plan_preserves_recovery() {
  local plan_path="$1"
  local recovery_json

  recovery_json="$(printf '%s\n' "${RECOVERY_ADDRESSES[@]}" | jq -R . | jq -s .)"
  terraform -chdir="$TF_DIR" show -json "$plan_path" \
    | jq -e --argjson recovery "$recovery_json" '
        all(.resource_changes[]?;
          (.change.actions | index("create") | not)
          and (.change.actions | index("update") | not)
        )
        and
        ([
          .resource_changes[]?
          | select(.address as $address | $recovery | index($address))
          | select(.change.actions | index("delete"))
        ] | length == 0)
      ' >/dev/null
}

recovery_service_account_ids() {
  jq -r '.service_account_id // empty' "$YC_SERVICE_ACCOUNT_KEY_FILE"
  state_resource_id 'yandex_iam_service_account.marketdb-tf'
  backend_service_account_id
  printf '%s\n' "$GITHUB_DEPLOY_SERVICE_ACCOUNT_ID"
}

cleanup_non_recovery_service_accounts() {
  local recovery_ids service_accounts ids id

  if ! recovery_ids="$(recovery_service_account_ids | awk 'NF' | sort -u | jq -R . | jq -s .)"; then
    echo "Unable to resolve every recovery service account; refusing IAM cleanup" >&2
    return 0
  fi
  if ! service_accounts="$(yc iam service-account list --format json 2>/dev/null)"; then
    echo "Unable to inspect IAM service accounts" >&2
    return 0
  fi

  ids="$(
    jq -r --argjson recovery "$recovery_ids" \
      '.[] | select(.id as $id | $recovery | index($id) | not) | .id' \
      <<< "$service_accounts"
  )"
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "Deleting non-recovery IAM service account $id"
    if ! yc iam service-account delete --id "$id"; then
      echo "Unable to delete IAM service account $id" >&2
    fi
  done <<< "$ids"
}

verify_empty() {
  local recovery_ids specification result filtered count failures=0
  local -a command_parts

  recovery_ids="$(recovery_service_account_ids | awk 'NF' | sort -u | jq -R . | jq -s .)"

  for specification in "${INVENTORY_COMMANDS[@]}"; do
    read -r -a command_parts <<< "$specification"
    if ! result="$(yc "${command_parts[@]}" list --format json 2>/dev/null)"; then
      echo "Unable to verify $specification" >&2
      failures=$((failures + 1))
      continue
    fi

    case "$specification" in
      "iam service-account")
        filtered="$(jq --argjson recovery "$recovery_ids" '[.[] | select(.id as $id | $recovery | index($id) | not)]' <<< "$result")"
        ;;
      "storage bucket")
        filtered="$(jq --arg state_bucket "$STATE_BUCKET" '[.[] | select(.name != $state_bucket)]' <<< "$result")"
        ;;
      *)
        filtered="$result"
        ;;
    esac

    count="$(jq 'length' <<< "$filtered")"
    if [[ "$count" -ne 0 ]]; then
      echo "Unexpected resources remain in $specification:" >&2
      jq -r '.[] | "  \(.id // "-")  \(.name // "-")"' <<< "$filtered" >&2
      failures=$((failures + 1))
    fi
  done

  if [[ "$failures" -ne 0 ]]; then
    echo "Folder is not empty outside the recovery control plane" >&2
    return 1
  fi
}

usage() {
  echo "Usage: $0 targets [all|core|storage]|assert-recovery-principal|assert-plan PLAN|inventory|cleanup-kubernetes-residuals|cleanup-known-residuals|cleanup-non-recovery-service-accounts|purge-bucket NAME|verify-empty" >&2
}

case "${1:-}" in
  targets)
    terraform_targets "${2:-all}"
    ;;
  assert-recovery-principal)
    assert_recovery_principal
    ;;
  assert-plan)
    [[ -n "${2:-}" ]] || {
      usage
      exit 2
    }
    assert_plan_preserves_recovery "$2"
    ;;
  inventory)
    inventory
    ;;
  cleanup-kubernetes-residuals)
    cleanup_kubernetes_residuals
    ;;
  cleanup-known-residuals)
    cleanup_known_residuals
    ;;
  cleanup-non-recovery-service-accounts)
    cleanup_non_recovery_service_accounts
    ;;
  purge-bucket)
    [[ -n "${2:-}" ]] || {
      usage
      exit 2
    }
    purge_bucket "$2"
    ;;
  verify-empty)
    verify_empty
    ;;
  *)
    usage
    exit 2
    ;;
esac
