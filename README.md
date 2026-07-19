# cloud-infrastructure

## Reversible Yandex Cloud teardown

The `Yandex Cloud lifecycle` workflow can remove the current infrastructure
without deleting its Terraform definition. A later `restore` recreates empty
databases, Redis, buckets, Kubernetes, Helm releases, DNS, certificates, and
CDN resources.

The recovery control plane is intentionally retained:

- Object Storage bucket `marketdb-tf-state`;
- Terraform service account `marketdb-tf`;
- folder IAM bindings `editor`, `k8s.clusters.agent`, `vpc.publicAdmin`, and
  `container-registry.images.puller` for that account;
- the backend access key and the GitHub Actions service-account key.

Do not delete or rotate that control plane while the infrastructure is down
unless the backend and GitHub secrets are migrated first.

### Teardown

1. Run `Yandex Cloud lifecycle` with action `inventory` and review everything
   reported for folder `b1g90io1nf34fov5esm5`.
2. Run it with action `plan-destroy` and review the Terraform destroy plan. The
   recovery resources above must not be present in the plan.
3. Run it with action `destroy` and confirmation
   `DESTROY b1g90io1nf34fov5esm5`.
4. Review the final inventory. The workflow automatically removes known
   Kubernetes load-balancer and disk leftovers; any other leftovers must be
   investigated before they are removed.

The destroy action permanently removes PostgreSQL, Redis, Object Storage data,
Kubernetes volumes, and application secrets. DNS names are unavailable until
restore completes.

### Restore

Run `Yandex Cloud lifecycle` with action `restore`. The workflow performs:

1. `terraform apply` against the retained remote state;
2. kubeconfig generation for the new cluster;
3. infra Helmfile deployment using the Terraform-managed static ingress IP;
4. recreation of `endmake-secrets` and the application Helmfile deployments;
5. DNS cutover to the provider CNAMEs generated for the new CDN resources;
6. a final Yandex Cloud inventory.

Set `restore_applications` to `false` to stop after Terraform and the infra
Helmfile. A full restore requires all secrets referenced by
`.github/workflows/yandex_lifecycle.yaml` to remain present in GitHub Actions.
