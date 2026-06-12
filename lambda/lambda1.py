import datetime, boto3, botocore, json, uuid


def lambda_ingest(event, context):
    with open('mock_transactions.json', 'r') as file:
        mock_transaction = json.load(file)

    date = datetime.datetime.now()
    eventbridge = boto3.client('events')
    Entry = []
    for entries in mock_transaction:
        if entries.get('is_duplicate') != True:
            entries['transaction_id'] = str(uuid.uuid4())
        json_string = json.dumps(entries)
        Entry.append(json_string)
        try:
            response = eventbridge.put_events(
            Entries=[
                {
                    'Time': date,
                    'Source': 'transaction.generator',
                    'DetailType': 'TransactionEvent',
                    'Detail': json_string,
                    'EventBusName': 'transaction-event-bus'
                },
            ],
        )
            if response['FailedEntryCount'] > 0:
                print("Entries failed")    
        except botocore.exceptions.ClientError as e:
            print(f"Put Events failed: {e}")


    


