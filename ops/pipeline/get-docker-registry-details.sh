## Get details for AWS ECR (Elastic Container Registry) in environment variables

ECR_AWS_ACCOUNT_ID="492475357299"
ECR_AWS_REGION="us-west-2"
DOCKER_REGISTRY_URL="${ECR_AWS_ACCOUNT_ID}.dkr.ecr.${ECR_AWS_REGION}.amazonaws.com"

# ppc64le uses Docker Hub instead of AWS ECR
if [[ "${arch:-}" == "ppc64le" ]]; then
  DOCKER_REGISTRY_URL="docker.io/sandeepkgupta12"
fi