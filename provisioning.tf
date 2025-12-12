resource "null_resource" "check_ratpay_exists" {
  triggers = {
    always = timestamp()
  }

  connection {
    type        = "ssh"
    host        = aws_eip.minikube.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.ec2_key.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "if [ -d /home/ubuntu/rat-pay ] && minikube status >/dev/null 2>&1; then",
      "  echo 'rat-pay exists and minikube is running'; exit 0;",
      "else",
      "  echo 'Cluster check failed (missing dir or stopped)'; exit 1;",
      "fi"
    ]

    on_failure = continue
  }

  depends_on = [aws_eip.minikube]
}

resource "null_resource" "upload_start_minikube" {
  triggers = {
    script_hash   = filemd5("${path.module}/scripts/start-minikube.sh")
    check_trigger = null_resource.check_ratpay_exists.id
  }

  connection {
    type        = "ssh"
    host        = aws_eip.minikube.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.ec2_key.private_key_pem
  }

  provisioner "file" {
    source      = "${path.module}/scripts/start-minikube.sh"
    destination = "/home/ubuntu/start-minikube.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/\r$//' /home/ubuntu/start-minikube.sh",
      "chmod +x /home/ubuntu/start-minikube.sh"
    ]
  }
}

resource "null_resource" "upload_stop_minikube" {
  triggers = {
    script_hash   = filemd5("${path.module}/scripts/stop-minikube.sh")
    check_trigger = null_resource.check_ratpay_exists.id
  }

  connection {
    type        = "ssh"
    host        = aws_eip.minikube.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.ec2_key.private_key_pem
  }

  provisioner "file" {
    source      = "${path.module}/scripts/stop-minikube.sh"
    destination = "/home/ubuntu/stop-minikube.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/\r$//' /home/ubuntu/stop-minikube.sh",
      "chmod +x /home/ubuntu/stop-minikube.sh"
    ]
  }
}

resource "null_resource" "upload_deploy_cluster" {
  triggers = {
    script_hash   = filemd5("${path.module}/scripts/deploy-cluster.sh")
    check_trigger = null_resource.check_ratpay_exists.id
  }

  connection {
    type        = "ssh"
    host        = aws_eip.minikube.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.ec2_key.private_key_pem
  }

  provisioner "file" {
    content     = templatefile("${path.module}/scripts/deploy-cluster.sh", { repository_url = var.repository_url })
    destination = "/home/ubuntu/deploy-cluster.sh"
  }

  provisioner "file" {
    source      = "${path.module}/secrets.yaml"
    destination = "/home/ubuntu/secrets.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/\r$//' /home/ubuntu/deploy-cluster.sh",
      "chmod +x /home/ubuntu/deploy-cluster.sh"
    ]
  }
}

resource "null_resource" "minikube_setup" {
  triggers = {
    instance_id   = aws_instance.rat-pay-minikube.id
    script_hash   = filemd5("${path.module}/minikube-setup.sh")
    check_trigger = null_resource.check_ratpay_exists.id
  }

  connection {
    type        = "ssh"
    host        = aws_eip.minikube.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.ec2_key.private_key_pem
  }

  provisioner "file" {
    source      = "${path.module}/minikube-setup.sh"
    destination = "/tmp/minikube-setup.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/\r$//' /tmp/minikube-setup.sh",
      "chmod +x /tmp/minikube-setup.sh",
      "sudo /tmp/minikube-setup.sh",
      "rm /tmp/minikube-setup.sh"
    ]
  }

  depends_on = [
    aws_eip.minikube,
    null_resource.upload_start_minikube,
    null_resource.upload_stop_minikube,
    null_resource.upload_deploy_cluster
  ]
}

resource "null_resource" "setup_ratpay" {
  triggers = {
    create_trigger = null_resource.check_ratpay_exists.id
  }

  connection {
    type        = "ssh"
    host        = aws_eip.minikube.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.ec2_key.private_key_pem
  }

  # Clone repo only if missing
  provisioner "remote-exec" {
    inline = [
      "if [ ! -d /home/ubuntu/rat-pay ]; then",
      "  git clone ${var.repository_url} /home/ubuntu/rat-pay;",
      "fi"
    ]
  }

  provisioner "file" {
    source      = "${path.module}/secrets.yaml"
    destination = "/home/ubuntu/rat-pay/k8s/secrets.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chown ubuntu:ubuntu /home/ubuntu/rat-pay/k8s/secrets.yaml",
      "rm -f /home/ubuntu/rat-pay/k8s/secrets.yaml.example"
    ]
  }

  depends_on = [null_resource.check_ratpay_exists]
}

# Runs only if some of pentest scripts have been changed
resource "null_resource" "setup_pentest" {
  triggers = {
    instance_id  = aws_instance.pentest.id
    scripts_hash = sha1(join("", [for f in fileset("${path.module}/pentest", "*") : filesha1("${path.module}/pentest/${f}")]))
  }

  connection {
    type        = "ssh"
    host        = aws_instance.pentest.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.ec2_key.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "if [ -d /home/ubuntu/pentest ]; then",
      "  mv /home/ubuntu/pentest /home/ubuntu/pentest.old",
      "  rm -rf /home/ubuntu/pentest",
      "fi"
    ]
  }

  provisioner "file" {
    source      = "${path.module}/pentest"
    destination = "/home/ubuntu/pentest"
  }

  # Upload Private Key for accessing Minikube from Pentest
  provisioner "file" {
    content     = tls_private_key.ec2_key.private_key_pem
    destination = "/home/ubuntu/pentest/rat-pay.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 400 /home/ubuntu/pentest/rat-pay.pem",
      "chmod +x /home/ubuntu/pentest/*.sh",
      "mkdir /home/ubuntu/pentest/reports/"
    ]
  }

  depends_on = [aws_instance.pentest]
}
