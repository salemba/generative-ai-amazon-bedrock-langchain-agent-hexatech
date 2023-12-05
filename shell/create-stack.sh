# If not already forked, fork the remote repository (https://github.com/aws-samples/generative-ai-amazon-bedrock-langchain-agent-example) and change working directory to shell folder
# cd generative-ai-amazon-bedrock-langchain-agent-example/shell/
# chmod u+x create-stack.sh
# source ./create-stack.sh
#Global vars Adde by SBA
#Forked repository URL from Pre-Deployment (Exclude '.git' from repository URL)
export AMPLIFY_REPOSITORY=https://github.com/salemba/generative-ai-amazon-bedrock-langchain-agent-hexatech
# GitHub PAT copied from Pre-Deployment
export GITHUB_PAT=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
# Stack name must be lower case for S3 bucket naming convention
# !!! Beware: When running this script multiple times, you need to change the bucket name even after you clean the stack.
# When you delete a bucket on AWS, it won't be deleted directly. It will take up to 3 hours until it is completeley removed.
export STACK_NAME=s3-bucket-sba-202312041016
# Public or internal HTTPS website for Kendra to index via Web Crawler (e.g., https://www.investopedia.com/) - Please see https://docs.aws.amazon.com/kendra/latest/dg/data-source-web-crawler.html
export KENDRA_WEBCRAWLER_URL=https://www.investopedia.com/ 
#region
# !! Important: when configuring your aws CLI, be sure to make the default region the same as this one. Else, you will face many errors regarding Cloudformation multi-region configuration  (Ex : An error occurred (ValidationError) when calling the CreateStack operation: Template format error: Unrecognized resource types: [AWS::Lex::Bot, AWS::Kendra::Index, AWS::Kendra::DataSource])
export REGION=us-east-1
#End of section
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export S3_ARTIFACT_BUCKET_NAME=$STACK_NAME-$ACCOUNT_ID
export DATA_LOADER_S3_KEY="agent/lambda/data-loader/loader_deployment_package.zip"
export LAMBDA_HANDLER_S3_KEY="agent/lambda/agent-handler/agent_deployment_package.zip"
export LEX_BOT_S3_KEY="agent/bot/lex.zip"

aws s3 mb s3://${S3_ARTIFACT_BUCKET_NAME} --region $REGION
aws s3 cp ../agent/ s3://${S3_ARTIFACT_BUCKET_NAME}/agent/ --recursive --exclude ".DS_Store"

export BEDROCK_LANGCHAIN_LAYER_ARN=$(aws lambda publish-layer-version \
    --layer-name bedrock-langchain-pypdf \
    --description "Bedrock LangChain PyPDF layer" \
    --license-info "MIT" \
	--region $REGION \
    --content S3Bucket=${S3_ARTIFACT_BUCKET_NAME},S3Key=agent/lambda-layers/bedrock-langchain-pypdf.zip \
    --compatible-runtimes python3.11 \
    --query LayerVersionArn --output text)

export GITHUB_TOKEN_SECRET_NAME=$(aws secretsmanager create-secret --name $STACK_NAME-git-pat \
--secret-string $GITHUB_PAT --region $REGION --query Name --output text)

echo "GITHUB_TOKEN_SECRET_NAME= $GITHUB_TOKEN_SECRET_NAME"
echo "STACK_NAME : $STACK_NAME"
aws cloudformation create-stack \
--stack-name ${STACK_NAME} \
--template-body file://../cfn/GenAI-FSI-Agent.yml \
--parameters \
--region $REGION \
ParameterKey=S3ArtifactBucket,ParameterValue=${S3_ARTIFACT_BUCKET_NAME} \
ParameterKey=DataLoaderS3Key,ParameterValue=${DATA_LOADER_S3_KEY} \
ParameterKey=LambdaHandlerS3Key,ParameterValue=${LAMBDA_HANDLER_S3_KEY} \
ParameterKey=LexBotS3Key,ParameterValue=${LEX_BOT_S3_KEY} \
ParameterKey=GitHubTokenSecretName,ParameterValue=${GITHUB_TOKEN_SECRET_NAME} \
ParameterKey=KendraWebCrawlerUrl,ParameterValue=${KENDRA_WEBCRAWLER_URL} \
ParameterKey=BedrockLangChainPyPDFLayerArn,ParameterValue=${BEDROCK_LANGCHAIN_LAYER_ARN} \
ParameterKey=AmplifyRepository,ParameterValue=${AMPLIFY_REPOSITORY} \
--capabilities CAPABILITY_NAMED_IAM

echo "Cloud formation stack creation in progress ..."
aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].StackStatus" --region $REGION
aws cloudformation wait stack-create-complete --stack-name $STACK_NAME --region $REGION

echo "AWS cloudformation stck created successfully!"
export LEX_BOT_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`LexBotID`].OutputValue' --output text)

echo "LEX_BOT_ID= $LexBotID "
export LAMBDA_ARN=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaARN`].OutputValue' --output text)
echo "LAMBDA ARN : $lambdaARN "
aws lexv2-models update-bot-alias --bot-alias-id 'TSTALIASID' --bot-alias-name 'TestBotAlias' --bot-id $LEX_BOT_ID --bot-version 'DRAFT' --bot-alias-locale-settings "{\"en_US\":{\"enabled\":true,\"codeHookSpecification\":{\"lambdaCodeHook\":{\"codeHookInterfaceVersion\":\"1.0\",\"lambdaARN\":\"${LAMBDA_ARN}\"}}}}"

echo "Updated Lex Bot alias"
aws lexv2-models build-bot-locale --bot-id $LEX_BOT_ID --bot-version "DRAFT" --locale-id "en_US"

echo "Lex bit built locally"
export KENDRA_INDEX_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`KendraIndexID`].OutputValue' --output text)
echo "KENDRA INDEX ID = $KENDRA_INDEX_ID"
export KENDRA_S3_DATA_SOURCE_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME --region $REGION\
    --query 'Stacks[0].Outputs[?OutputKey==`KendraS3DataSourceID`].OutputValue' --output text)

export KENDRA_WEBCRAWLER_DATA_SOURCE_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`KendraWebCrawlerDataSourceID`].OutputValue' --output text)

echo "KENDRA_WEBCRAWLER_DATA_SOURCE_ID = $KENDRA_WEBCRAWLER_DATA_SOURCE_ID"
echo "Kendra starting datasource sync ..."
aws kendra start-data-source-sync-job --id $KENDRA_S3_DATA_SOURCE_ID --index-id $KENDRA_INDEX_ID

aws kendra start-data-source-sync-job --id $KENDRA_WEBCRAWLER_DATA_SOURCE_ID --index-id $KENDRA_INDEX_ID

export AMPLIFY_APP_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`AmplifyAppID`].OutputValue' --output text)

export AMPLIFY_BRANCH=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`AmplifyBranch`].OutputValue' --output text)
echo "AMPLIFY_APP_ID : $AMPLIFY_APP_ID - AMPLIFY_BRANCH : $AMPLIFY_BRANCH"
aws amplify start-job --app-id $AMPLIFY_APP_ID --branch-name $AMPLIFY_BRANCH --job-type 'RELEASE'
# Build might fail du to github connection problems. Log in to your AWS console and rerun build. Should be OK then

# Once your website deployed, you will need to plug the Kommunicate Widget in order to chat with the agent. See post deployment section in tyhe project documentation
