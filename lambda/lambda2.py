import boto3, datetime, os

sns = boto3.client('sns')
dynamodb = boto3.client('dynamodb')

#check for successful transactions
def successful(event, context):
    if event['detail']['requested_amount'] == event['detail']['approved_amount']:
        return 'Successful Payment'

#check for failed transactions
def failed(event, context):
    if event['detail']['requested_amount'] > event['detail']['approved_amount']:
        return 'Failed Payment'
    
#check if transactions timed out
def timeout(event, context):
    time = datetime.datetime.strptime(event['detail']['approved_time'], "%Y-%m-%d %H:%M:%S") - datetime.datetime.strptime(event['detail']['transaction_time'], "%Y-%m-%d %H:%M:%S")
    if time.total_seconds() / 60 > 5:
        return 'Payment has timed out'
    
#check for duplicate transactions:
def duplicate(event, context):
    try:
        dynamodb.put_item(
            TableName='TransactionTable',
            Item={
                'transaction_id': {'S': event['detail']['transaction_id']},
                'to_account': {'S': event['detail']['to_account']},
                'requested_amount': {'N': str(event['detail']['requested_amount'])}
            },
            ConditionExpression='attribute_not_exists(transaction_id)'
        )
    except dynamodb.exceptions.ConditionalCheckFailedException:
        return 'Duplicate Transaction'
            
    
  
#message format
def format_message(event, anomaly_type):
    d = event['detail']
    return (
        f"ALERT: {anomaly_type}\n\n"
        f"Transaction ID:   {d['transaction_id']}\n"
        f"Type:             {d['transaction_type']}\n"
        f"Beneficiary:      {d['beneficiary_name']} ({d['to_account']})\n"
        f"Requested Amount: ₦{d['requested_amount']:,.2f}\n"
        f"Approved Amount:  ₦{d['approved_amount']:,.2f}\n"
        f"Receiving Bank:   {d['received_bank']}\n"
        f"Transaction Time: {d['transaction_time']}\n"
        f"Approved Time:    {d['approved_time']}\n"
    )

#takes the 4 functions,puts them together and publishes to SNS
def lambda_processor(event, context):

    if successful(event, context):
        response = sns.publish(
        TopicArn=os.environ.get('SNS_TOPIC_ARN'),
        Message=format_message(event, 'Successful Payment'),
        Subject= event['detail']['transaction_id'] + ' - Payment Confirmed.',
    )
    
    if failed(event, context):
        response = sns.publish(
        TopicArn=os.environ.get('SNS_TOPIC_ARN'),
        Message=format_message(event, 'Failed Payment'),
        Subject= event['detail']['transaction_id'] + ' - Failed.',
    )
        
    if timeout(event, context):
        response = sns.publish(
        TopicArn=os.environ.get('SNS_TOPIC_ARN'),
        Message=format_message(event, 'Timeout'),
        Subject= event['detail']['transaction_id'] + ' - Timed Out.',
    )
        
    if duplicate(event, context):
        response = sns.publish(
        TopicArn=os.environ.get('SNS_TOPIC_ARN'),
        Message=format_message(event, 'Duplicate Charge'),
        Subject=event['detail']['transaction_id'] + ' - was a Duplicate Payment.'
    )