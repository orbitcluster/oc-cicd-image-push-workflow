#!/bin/bash
set -e

# Construct the repository name with the image name
REPO_NAME="${ORGID}-${BUID}-${APPID}/${IMAGE_NAME}"
echo "Repository Name: $REPO_NAME"


# Check if repository exists
if ! aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$REGION" > /dev/null 2>&1; then
  echo "Repository $REPO_NAME does not exist. Creating..."
  aws ecr create-repository --repository-name "$REPO_NAME" --region "$REGION" --tags "Key=orgid,Value=${ORGID}" "Key=buid,Value=${BUID}" "Key=appid,Value=${APPID}"
else
  echo "Repository $REPO_NAME already exists."
fi

# Docker Push Logic
IFS=',' read -ra TAG_ARRAY <<< "$TAGS"

# Find a valid source tag from the local images
SOURCE_TAG=""
for t in "${TAG_ARRAY[@]}"; do
  t="${t// /}"
  if [ -n "$t" ] && docker image inspect "$IMAGE_NAME:$t" >/dev/null 2>&1; then
    SOURCE_TAG="$t"
    break
  fi
done

# Fallback if no tag from the list exists locally
if [ -z "$SOURCE_TAG" ]; then
  if docker image inspect "$IMAGE_NAME:latest" >/dev/null 2>&1; then
    SOURCE_TAG="latest"
  else
    # Let it fail naturally on the first tag
    SOURCE_TAG="${TAG_ARRAY[0]// /}"
  fi
fi

for raw_tag in "${TAG_ARRAY[@]}"; do
  TAG="${raw_tag// /}"
  if [ -z "$TAG" ]; then
    continue
  fi

  ECR_IMAGE="$REGISTRY/$REPO_NAME:$TAG"
  echo "Tagging image as $ECR_IMAGE"

  if docker image inspect "$IMAGE_NAME:$TAG" >/dev/null 2>&1; then
    docker tag "$IMAGE_NAME:$TAG" "$ECR_IMAGE"
  else
    echo "Warning: Local image $IMAGE_NAME:$TAG not found. Using $IMAGE_NAME:$SOURCE_TAG as source."
    docker tag "$IMAGE_NAME:$SOURCE_TAG" "$ECR_IMAGE"
  fi

  echo "Pushing image to ECR"
  docker push "$ECR_IMAGE"
done
