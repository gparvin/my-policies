# my-policies

## Policies

Some policies I have created.

File | Description
---  | ---
policy-acs-alerts.yaml | Look for PolicyReport v1alpha2 resources that contain failures.
policy-acs-integrations.yaml | Create the integrations for ACS.  WIP  More is needed.
policy-acs-policies.yaml | Define ACS policies that can be synced with ACS.
policy-check-acs-managed.yaml | Any managed cluster that is missing secure cluster services will be noncompliant
policy-gatekeeper-container-require-resources.yaml | A gatekeeper policy to alert on missing resources requests from a deployment
policy-install-acs-central.yaml | Create an ACS Central application using a policy
policy-kyverno-pod-resources.yaml | Policy that wraps the kyverno resources policy
policy-kyverno-sample.yaml | Sample
policy-ocp-check-fips.yaml | Make sure fips is enabled
policy-pod-resources.yaml | Not an easy way to validate resource requests using a config policy
policy-secured-cluster-helm-local-cluster.yaml | A template for providing helm config to systems that already have the base layer of secured cluster services setup.


## Apps

Sample Apps

File | Description
--- | ---
policy-install-acs-central.yaml | How to wrap a helm chart inside a policy
kyverno-git.yaml | The kyverno app from git that works on OCP
