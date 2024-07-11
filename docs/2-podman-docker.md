# 2. Using crun-vm as a Podman or Docker runtime

Here we overview some of the major features provided by crun-vm. The commands
below use `podman`, but unless otherwise stated you can simply replace it with
`docker`.

## Booting VMs

### From regular VM image files

First, obtain a QEMU-compatible VM image and place it in a directory by itself:

```console
$ mkdir my-vm-image
$ curl -LO --output-dir my-vm-image https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-Generic.x86_64-40-1.14.qcow2
```

Then run:

> This example does not work with Docker, as docker-run does not support the
> `--rootfs` flag; see the next section for a Docker-compatible way of running
> VM images.

```console
$ podman run \
    --runtime crun-vm \
    -it --rm \
    --rootfs my-vm-image \
    ""  # unused, but must specify command
```

The VM console should take over your terminal. At this point, the
qcow2 image does not have any ssh keys, root password, or alternative
users installed, so although you can interact with the VM's login
screen, you will be unable to access a command prompt until more
options are used in later sections.  To abort the VM, press `ctrl-]`.

You can also detach from the VM without terminating it by pressing `ctrl-p,
ctrl-q`. Afterwards, reattach by running:

```console
$ podman attach --latest
```

This command also works when you start the VM in detached mode using
podman-run's `-d`/`--detach` flag.

It is also possible to omit flags `-i`/`--interactive` and `-t`/`--tty` to
podman-run, in which case you won't be able to interact with the VM but can
still observe its console. Note that pressing `ctrl-]` will have no effect, but
you can always use the following command to terminate the VM:

> For this command to work with Docker, you must replace the `--latest` flag
> with the container's name or ID.

```container
$ podman stop --latest
```

Changes made by the VM to its image are by default not persisted in the original
image file. This can be changed by passing in the non-standard option
`--persistent` *after* the `--rootfs` option:

```console
$ podman run \
    --runtime crun-vm \
    -it --rm \
    --rootfs my-vm-image \
    --persistent
```

> [!WARNING]
>
> When using `--persistent`, make sure that the image file is never
> simultaneously used by another process or VM, otherwise **data corruption may
> occur**.

### From VM image files packaged into container images

crun-vm also works with container images that contain a VM image file with
any name under `/` or under `/disk/`. No other files may exist in those
directories. Containers built for use as [KubeVirt `containerDisk`s] follow this
convention, so you can use those here:

```console
$ podman run \
    --runtime crun-vm \
    -it --rm \
    quay.io/containerdisks/fedora:40
```

You can also use `util/package-vm-image.sh` to easily package a VM image into a
container image, and `util/extract-vm-image.sh` to extract a VM image contained
in a container image.

Note that flag `--persistent` has no effect when running VMs from container
images.

### From bootable container images

crun-vm can also work with [bootable container images], which are containers
that package a full operating system:

```console
$ podman run \
    --runtime crun-vm \
    -it --rm \
    quay.io/crun-vm/example-fedora-bootc:40
```

Internally, crun-vm generates a VM image from the bootable container and then
boots it.

## First-boot customization

### cloud-init

In the examples above, you were able to boot the VM but not to log in. To fix
this and do other first-boot customization, you can provide a [cloud-init]
NoCloud configuration to the VM by passing in the non-standard option
`--cloud-init` *after* the image specification:

```console
$ ls examples/cloud-init/config/
meta-data  user-data  vendor-data

$ podman run \
    --runtime crun-vm \
    -it --rm \
    quay.io/containerdisks/fedora:40 \
    --cloud-init ~/examples/cloud-init/config  # path must be absolute
```

You should now be able to log in with the default `fedora` username and password
`pass`.

Alternatively, you can set the default user's password with the `--password`
option:

```console
$ podman run \
    --runtime crun-vm \
    -it --rm \
    quay.io/containerdisks/fedora:40 \
    --password pass
```

### Ignition

Similarly, you can provide an [Ignition] configuration to the VM by passing in
the `--ignition` option:

```console
$ podman run \
    --runtime crun-vm \
    -it --rm \
    quay.io/crun-vm/example-fedora-coreos:40 \
    --ignition ~/examples/ignition/config.ign  # path must be absolute
```

You should now be able to log in with the default `core` username and password
`pass`.

Note that the `--password` option requires cloud-init support and doesn't work
if the VM uses Ignition.

## SSH'ing into the VM

Assuming the VM supports cloud-init or Ignition and exposes an SSH server on
port 22, you can `ssh` into it as root using podman-exec:

> For this command to work with Docker, you must replace the `--latest` flag
> with the container's name or ID.

```console
$ podman run \
    --runtime crun-vm \
    --detach --rm \
    quay.io/containerdisks/fedora:40
8068a2c180e0f4bf494f5e0baa37d9f13a9810f76b361c0771b73666e47ec383

$ podman exec --latest whoami
Please login as the user "fedora" rather than the user "root".
```

This particular VM image does not allow logging in as root. To `ssh` into the VM
as a different user, specify its username using the `--as` option immediately
before the command (if any). You may need to pass in `--` before this option to
prevent podman-exec from trying to interpret it:

```console
$ podman exec --latest -- --as fedora whoami
fedora
```

If you just want a login shell, pass in an empty string as the command. The
following would be the output if this VM image allowed logging in as root:

```
$ podman exec -it --latest ""
[root@8068a2c180e0 ~]$
```

You can also log in as a specific user:

```
$ podman exec -it --latest -- --as fedora
[fedora@8068a2c180e0 ~]$
```

When the VM supports cloud-init, `authorized_keys` is automatically set up to
allow SSH access by podman-exec for users `root` and the default user as set in
the image's cloud-init configuration. With Ignition, this is set up for users
`root` and `core`.

> If you want to exec into the container in which the VM is running (probably to
> debug some problem with crun-vm itself), pass in the `--container` flag
> immediately before the command (if any).

## Port forwarding

You can use podman-run's standard `-p`/`--publish` option to set up TCP and/or
UDP port forwarding:

```console
$ podman run \
    --runtime crun-vm \
    --detach --rm \
    -p 8000:80 \
    quay.io/crun-vm/example-http-server:latest
36c8705482589cfc4336a03d3802e7699f5fb228123d18e693488ac7b80116d1

$ curl localhost:8000
<!DOCTYPE HTML>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Directory listing for /</title>
</head>
<body>
[...]
```

## Passing things through to the VM

### Directories

Bind mounting directories into the VM is supported:

> [!WARNING]
>
> This example recursively modifies the SELinux context of all files under the
> path being mounted, in this case `./util`, which in the worst case **may cause
> you to lose access to your files**. This is due to the `:z` volume mount
> modifier, which instructs Podman to relabel the volume so that the VM can
> access it.
>
> Alternatively, you may remove this modifier from the command below and add
> `--security-opt label=disable` instead to disable SELinux enforcement.

```console
$ podman run \
    --runtime crun-vm \
    -it --rm \
    -v ./util:/home/fedora/util:z \
    quay.io/containerdisks/fedora:40 \
    --password pass
```

If the VM supports cloud-init or Ignition, the volume will automatically be
mounted at the given destination path. Otherwise, you can mount it manually with
the following command, where `<index>` must be the 0-based index of the volume
according to the order the `-v`/`--volume` or `--mount` flags where given in:

```console
$ mount -t virtiofs virtiofs-<index> /home/fedora/util
```

### Regular files

Similarly to directories, you can bind mount regular files into the VM:

> [!WARNING]
>
> The warning about SELinux relabeling on the command above also applies here.

```console
$ podman run \
    --runtime crun-vm \
    -it --rm \
    -v ./README.md:/home/fedora/README.md:z \
    quay.io/containerdisks/fedora:40 \
    --password pass
```

Regular files currently appear as block devices in the VM, but this is subject
to change.

### Block devices

If cloud-init or Ignition are supported by the VM, it is possible to pass block
devices through to it at a specific path using podman-run's `--device` flag
(this example assumes `/dev/ram0` to exist and to be accessible by the current
user):

```console
$ podman run \
    --runtime crun-vm \
    -it --rm \
    --device /dev/ram0:/home/fedora/my-disk \
    quay.io/containerdisks/fedora:40 \
    --password pass
```

You can also use the more powerful `--blockdev
source=<path>,target=<path>,format=<fmt>` custom option to this effect. This
option also allows you specify a regular file as the source, and the source may
be in any disk format known to QEMU (*e.g.*, raw, qcow2; when using `--device`,
raw format is assumed):

```console
$ podman run \
    --runtime crun-vm \
    -it --rm \
    quay.io/containerdisks/fedora:40 \
    --password pass \
    --blockdev source=~/my-disk.qcow2,target=/home/fedora/my-disk,format=qcow2  # paths must be absolute
```

## Advanced options

### System emulation

To use system emulation instead of hardware-assisted virtualization, specify the
`--emulated` flag. Without this flag, attempting to create a VM on a host tbat
doesn't support KVM will fail.

It's not currently possible to use this flag when the container image is a bootc
bootable container.

### Inspecting and customizing the libvirt domain XML

crun-vm internally uses [libvirt] to launch a VM, generating a [domain XML
definition] from the options provided to podman-run. This XML definition can be
printed by adding the non-standard `--print-libvirt-xml` flag to your podman-run
invocation.

The generated XML definition can also be customized by specifying an XML file to
be merged with it using the non-standard option `--merge-libvirt-xml <file>`.

> [!NOTE]
>
> While `--merge-libvirt-xml` gives you maximum flexibility, it thwarts
> crun-vm's premise of isolating the user from such details as libvirt domain
> definitions, and you have instead to take care that your XML is valid *and*
> that the customized definition is compatible with what crun-vm expects.
>
> Before using this flag, consider if you would be better served using libvirt
> directly to manage your VM.

[bootable container images]: https://containers.github.io/bootable/
[cloud-init]: https://cloud-init.io/
[domain XML definition]: https://libvirt.org/formatdomain.html
[Ignition]: https://coreos.github.io/ignition/
[KubeVirt `containerDisk`s]: https://kubevirt.io/user-guide/virtual_machines/disks_and_volumes/#containerdisk
[libvirt]: https://libvirt.org/
