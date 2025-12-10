# shiftstack-ci

This repository contains tools to help build and simplify a testing environment
for the development of OpenShift 4.x installation against an OpenStack cloud.

## Prerequisites

Access to an OpenStack cloud fitting the [OpenShift on OpenStack
requirements](https://github.com/openshift/installer/tree/master/docs/user/openstack).

The RHCOS image can be downloaded from the [release
browser](https://releases-redhat-coreos-dev.cloud.paas.upshift.redhat.com).

It may be possible that the flavors available from your OpenStack cloud
provider set a disk size smaller than what is required for the rhcos image. If
that's the case, you can shrink the image with `qemu-img`, for instance:

```
qemu-img resize rhcos-maipo-400.7.20190312.0-openstack.qcow2 --shrink 10G
```

Additionally the cloud must have enough capacity for:
- 7 m1.medium nodes
- 1 floating IP

Finally, you'll need a go dev environment for building the installer.  [This
guide](https://medium.com/@fsufitch/go-environment-setup-minus-the-insanity-b872f34351c8)
has gifs of cats, and is highly recommended if you are struggling with this.

## Set up

Before running any of the scripts in this repository, there is minimal setup
required.

You will need to clone the [openshift
installer](http://github.com/openshift/installer). Rather than clone using
`git`, it is much more convenient to use `go get`, since it will put it where
it belongs for you.

```bash
go get github.com/openshift/installer
```

Make sure to export the `OS_CLOUD` environment variable to the name of your
OpenStack cloud provider from your `$HOME/.config/openstack/clouds.yaml` file.

Lastly, you need some binaries to work with OpenShift and OpenStack. This is
easy, just run:

```bash
sudo dnf install jq python-openstackclient
```

## Cluster Configuration

Make a copy of the `cluster_config.sh.example` file:

```shell
cp cluster_config.sh.example cluster_config.sh
```

Adjust the settings to match your environment. This will set up how and
where your cluster gets built, so it is important to fill it out carefully.
Here is a rundown of the important fields you will likely have to modify:

```
OS_CLOUD           The cloud in your openstack cluster that resources will be consumed from.
CLUSTER_NAME       What your ocp cluster will be nicknamed. This naming scheme is propogated to all resources in the cluster.
```

Finally you need to obtain a pull secret from [here](https://cloud.redhat.com/openshift/install/osp/installer-provisioned),
and replace `PULL_SECRET` variable with the new value. If you don't do this
you can still install the cluster, but you won't be able to create new
applications in OpenShift because you won't have access to private images.

Once this has been set up, you can proceed with building the installer.

## Building the Installer

Just run the convenience script: `build_ocp.sh`! You will have to do this
before your first run, and every time you make a change to the installer.

## Deploying OpenShift

This part is also pretty self-explanatory, the `run_ocp.sh` script will create
a cluster, and the `destroy_cluster.sh` script will destroy it. Moving
forwards, however, we will be looking to move away from building the cluster
this way, and towards using the [CI
operator](https://github.com/openshift/ci-operator/) as our primary means of
testing.

## Auditing CI Jobs Configuration

Audits CI configuration files to find OpenStack e2e test jobs and reports
their run_if_changed and skip_if_only_changed settings.

Usage: python hack/openstack-job-audit.py <project_path> [output_file]
  project_path: Path to the local copy of the release repo
  output_file: Output file path (default: ./openstack-ci-report.yaml)

Example: ./openstack-job-audit.py /path/to/openshift/release ./report.yaml
