resource "proxmox_vm_qemu" "k3s_servers" {
    # cloud-init template
    cicustom = "user=local:snippets/init-servers.yaml"
    count = 3
    # general
    target_node = "zeus"
    vmid = 100 + count.index
    name = "k3s-server-${count.index + 1}"
    pool = "containers"
    onboot = true
    agent = 1
    # os
    clone = "ubuntu-server-24.04-cloud-init"
    boot = "order=scsi0"
    # system
    bios = "seabios"
    scsihw = "virtio-scsi-pci"
    # disks
    disk {
        slot = "scsi1"
        type = "cloudinit"
        storage = "local-lvm"
    }
    disk {
        slot = "scsi0"         
        type = "disk"
        storage = "local-lvm"
        format = "raw"
        size = "32G"

        cache = "none"
        discard = true
        emulatessd = true
    }
    # cpu
    sockets = 1
    cores = 2
    cpu_type = "x86-64-v2-AES"
    # memory
    memory = 4096
    balloon = 512
    # network
    network {
        id = 0
        model = "virtio"
        bridge = "vmbr0"
        firewall = false
        link_down = false
    }
    # console output
    vga {
        type = "std"
    }
    # cloudinit
    ipconfig0 = "gw=${data.sops_file.network-secrets.data["network.gateway"]},ip=${data.sops_file.network-secrets.data["network.prefix"]}.${70 + count.index}/${data.sops_file.network-secrets.data["network.cidr"]}"
    nameserver = "${data.sops_file.network-secrets.data["network.nameserver"]}"
}
