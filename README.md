todo:
1. move scripts into directory
2. refactor main.tf (split into files)
3. add redeploy-script to main.tf
4. review provision rules

5. add transactions list page
6. separate ec2 instance for pentest



Start:
terraform validate
terraform plan
terraform apply
ssh into ec2 instance
./start-minikube.sh
./start-cluster.sh
if needed ./redeploy-app.sh
