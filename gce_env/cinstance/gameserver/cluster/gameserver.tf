output "gameserver" {
    value = "${join("\n", google_compute_instance.gameserver.*.network_interface.0.address)}"
}

resource "template_file" "env" {
    template = "${file("./templates/gameserver.env")}"
    vars {
    }
}

resource "template_file" "consul" {
    count = "${var.server_count}"
    template = "${file("./templates/consul.json")}"
    vars {
        node_name = "${var.cluster_name}-gameserver${count.index}"
        datacenter = "${var.consul_datacetner}"
        servers = "${var.consul_servers}"
    }
}

resource "template_file" "nomad" {
    count = "${var.server_count}"
    template = "${file("./templates/nomad.hcl")}"
    vars {
        node_name = "${var.cluster_name}-gameserver${count.index}"
        datacenter = "${var.consul_datacetner}"
        servers = "${var.nomad_servers}"
        region = "${var.region}"
    }
}

resource "template_file" "server_address" {
    template = "${file("../server_address.sh")}"
    vars {
    }
}

provider "google" {
    credentials = "${file("${var.account_file}")}"
    project = "${var.project}"
    region = "${var.region}"
}

resource "google_compute_instance" "gameserver" {
    count = "${var.server_count}"

    name = "${var.cluster_name}-gameserver${count.index}"
    machine_type = "n1-standard-2"
    can_ip_forward = true
    zone = "${var.zone}"
    tags = ["gameserver"]

    disk {
        image = "${var.image}"
        size = 200
    }

    network_interface {
        network = "default"
        access_config {
            // Ephemeral IP
        }
    }

    metadata {
        "sshKeys" = "${var.sshkey_metadata}"
    }

    provisioner "remote-exec" {
        inline = [
            "cat <<'EOF' > /tmp/server_address.sh\n${template_file.server_address.rendered}\nEOF",
            "sudo chmod +x /tmp/server_address.sh",
            "sudo mv /tmp/server_address.sh /opt/bin/server_address.sh",
            "cat <<'EOF' > /tmp/server.env\n${template_file.env.rendered}\nEOF",
            "echo 'ETCD_NAME=${self.name}' >> /tmp/server.env",
            "echo 'ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379' >> /tmp/server.env",
            "echo 'ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380' >> /tmp/server.env",
            "echo 'ETCD_INITIAL_ADVERTISE_PEER_URLS=http://${self.network_interface.0.address}:2380' >> /tmp/server.env",
            "echo 'ETCD_ADVERTISE_CLIENT_URLS=http://${self.network_interface.0.address}:2379' >> /tmp/server.env",
            "cat <<'EOF' > /tmp/consul.json\n${element(template_file.consul.*.rendered, count.index)}\nEOF",
            "cat <<'EOF' > /tmp/nomad.hcl\n${element(template_file.nomad.*.rendered, count.index)}\nEOF",
            "sudo mv /tmp/server.env /opt/etc/server.env",
            "sudo mv /tmp/consul.json /opt/etc/consul.d/consul.json",
            "sudo mv /tmp/nomad.hcl /opt/etc/nomad.d/nomad.hcl",
            "sudo /opt/bin/server_address.sh /opt/etc/nomad.d/nomad.hcl ${self.network_interface.0.address}",
        ]
        connection {
            user = "core"
            agent = true
        }
    }

    depends_on = [
        "template_file.env",
        "template_file.consul",
        "template_file.nomad",
    ]
}