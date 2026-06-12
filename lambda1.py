import uuid, datetime, boto3, botocore, json


def lambda_generate(event, context):
    date = datetime.datetime.now()
    transaction_id = uuid.uuid4()
    mock_transaction = [
        {
            "transaction_id": uuid.uuid4(),
            "transaction_type": "Debit",
            "transaction_time": date,
            "approved_time": date + datetime.timedelta(minutes=4),
            "beneficiary_name": "John Doe",
            "to_account": "0930397612",
            "narration": "Buy the dough",
            "requested_amount": 10000.00,
            "approved_amount": 10000.00,
            "received_bank": "032"
        },
        {
            "transaction_id": uuid.uuid4(),
            "transaction_type": "Debit",
            "transaction_time": date,
            "approved_time": date + datetime.timedelta(minutes=4),
            "beneficiary_name": "John Doe",
            "to_account": "0930397612",
            "narration": "Buy the dough",
            "requested_amount": 10000.00,
            "approved_amount": 5000.00,
            "received_bank": "032"
        },
        {
            "transaction_id": transaction_id,
            "transaction_type": "Debit",
            "transaction_time": date,
            "approved_time": date + datetime.timedelta(minutes=3),
            "beneficiary_name": "John Doe",
            "to_account": "0930397612",
            "narration": "Buy the dough",
            "requested_amount": 10000.00,
            "approved_amount": 10000.00,
            "received_bank": "032"
        },
        {
            "transaction_id": transaction_id,
            "transaction_type": "Debit",
            "transaction_time": date,
            "approved_time": date + datetime.timedelta(minutes=2),
            "beneficiary_name": "John Doe",
            "to_account": "0930397612",
            "narration": "Buy the dough",
            "requested_amount": 10000.00,
            "approved_amount": 10000.00,
            "received_bank": "032"
        },
        {
            "transaction_id": uuid.uuid4(),
            "transaction_type": "Debit",
            "transaction_time": date,
            "approved_time": date + datetime.timedelta(minutes=7),
            "beneficiary_name": "John Doe",
            "to_account": "0930397612",
            "narration": "Buy the dough",
            "requested_amount": 10000.00,
            "approved_amount": 10000.00,
            "received_bank": "032"
        }
    ]
    # eventbridge = boto3.client('eventbridge')
    eventbridge = boto3.client('events')
    Entry = []
    for entries in mock_transaction:
        entries['transaction_time'] = entries['transaction_time'].strftime("%Y-%m-%d %H:%M:%S")
        entries['approved_time'] = entries['approved_time'].strftime("%Y-%m-%d %H:%M:%S")
        entries['transaction_id'] = str(entries['transaction_id'])
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

    


