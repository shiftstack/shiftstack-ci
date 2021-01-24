# How to get credentials

It's critical to correctly configure the credentials here or the building process will fail with permission errors.

For registry.ci.openshift.org, you first need to copy the token from https://oauth-openshift.apps.ci.l2s4.p1.openshiftapps.com/oauth/token/request (top left, "Display Token") and run this command:

```sh
podman login --authfile <authfile> -u <username> -p <token> https://registry.ci.openshift.org
```

The right credentials should be updated in the authfile, that will be used to build the images later.

For quay.io, the credentials that need to be taken are from https://cloud.redhat.com/openshift/install/openstack/installer-provisioned

**NOTE:** Do not use your personal credentials, they won't work.
