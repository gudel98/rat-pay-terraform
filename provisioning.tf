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
    inline = ["chmod +x /home/ubuntu/start-minikube.sh"]
  }
}

# Upload deploy-cluster.sh (runs if updated OR if rat-pay check runs)
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
    source      = "${path.module}/scripts/deploy-cluster.sh"
    destination = "/home/ubuntu/deploy-cluster.sh"
  }

  provisioner "remote-exec" {
    inline = ["chmod +x /home/ubuntu/deploy-cluster.sh"]
  }
}

# Run setup script on the instance (runs if updated OR if rat-pay check runs)
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
      "chmod +x /tmp/minikube-setup.sh",
      "sudo /tmp/minikube-setup.sh",
      "rm /tmp/minikube-setup.sh"
    ]
  }

  depends_on = [
    aws_eip.minikube,
    null_resource.upload_start_minikube,
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
      "  git clone https://github.com/gudel98/rat-pay.git /home/ubuntu/rat-pay;",
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
      "rm /home/ubuntu/rat-pay/k8s/secrets.yaml.example"
    ]
  }

  depends_on = [null_resource.check_ratpay_exists]
}
