

# Logs Insights

`fields @timestamp, @message
| filter eventType = "Bounce" or eventType = "Complaint"
| sort @timestamp desc
| limit 1000`