# RatPay Infrastructure (Terraform)

This project uses Terraform to provision an AWS EC2 instance running a single-node Kubernetes cluster (Minikube) for the RatPay application.

## 🚀 Project Structure

- **`main.tf`**: Core infrastructure definitions (EC2, Security Groups, Key Pair).
- **`provisioning.tf`**: Server provisioning logic (Minikube installation, repo cloning, script uploads).
- **`variables.tf`**: Configuration variables.
- **`minikube-setup.sh`**: Script executed by Terraform to install Docker, Kubectl, and Minikube.
- **`scripts/`**: Helper scripts uploaded to the server:
  - `start-minikube.sh`: Starts the Minikube cluster (useful after a reboot).
  - `deploy-cluster.sh`: The **master script** for deploying code updates, building images, and managing port forwarding.

---

## 🛠️ Prerequisites

1.  **Terraform** installed (v1.0+).
2.  **AWS CLI** configured with appropriate credentials.
3.  A `secrets.yaml` file present in this directory (will be uploaded to the server).

---

## ⚡ Installation & First Run

1.  **Initialize Terraform:**
    ```bash
    terraform init
    ```

2.  **Review and Apply:**
    ```bash
    terraform validate
    terraform plan
    terraform apply
    ```

    > **Note:** This process:
    > *   Creates an EC2 instance and Elastic IP.
    > *   Installs Docker, Minikube, and Kubectl.
    > *   Clones the application repository (`https://github.com/gudel98/rat-pay.git`).
    > *   Uploads your `secrets.yaml`.
    > *   Uploads the helper scripts (`deploy-cluster.sh`, etc.) to `/home/ubuntu/`.

3.  **Connect to the Server:**
    Terraform outputs the exact SSH command.
    ```bash
    ssh -i <private_key>.pem ubuntu@<PUBLIC_IP>
    ```

4.  **Initial Deployment:**
    Once logged in, run setup script and deployment script to start the cluster and application:
    ```bash
    ./start-minikube.sh
    ./deploy-cluster.sh
    ```

---

## 🔄 Redeploying Application Code

To update the application with the latest code from GitHub:

1.  **SSH into the server:**
    ```bash
    ssh -i <private_key>.pem ubuntu@<PUBLIC_IP>
    ```

2.  **Run the deployment script:**
    ```bash
    ./deploy-cluster.sh
    ```

    **This script automatically:**
    *   Disables port forwarding (to allow image pulling).
    *   Backs up the current directory (`rat-pay` → `rat-pay-old`).
    *   Pulls the latest code from GitHub.
    *   Rebuilds the Docker image (`rat_pay_app:latest`).
    *   Updates the deployment in Minikube (`rollout restart`).
    *   Re-enables port forwarding (mapping port 80/443 → Ingress).

    > **Note:** Port-forwarding is essential as minikube cannot automatically map host ports to nginx-ingress.

---

## 🛡️ Secrets Management

*   **Local:** Keep your `secrets.yaml` in this Terraform directory.
*   **Updates:** If you change `secrets.yaml` locally, simply run `terraform apply` again to update it on the server.

---

## 🐀 https://rat-pay.online
