# Admin: approve / reject delivery partners

## After partner registers

1. Partner completes 3-step registration + OTP
2. Status becomes `pending_review` on `drivers.verification_status`
3. Documents are in Storage bucket `driver-documents/{driver_id}/`
4. Admin reviews → approve or reject
5. Only **approved** partners can turn Online and receive orders

## Review queue (SQL)

```sql
select
  d.id,
  d.full_name,
  d.phone,
  d.email,
  d.vehicle_type,
  d.vehicle_number,
  d.licence_number,
  d.address,
  d.submitted_at,
  d.verification_status
from public.drivers d
where d.verification_status = 'pending_review'
order by d.submitted_at asc;
```

Documents:

```sql
select * from public.driver_documents where driver_id = '<uuid>';
```

## Approve

```sql
select public.admin_review_partner(
  '<driver_uuid>'::uuid,
  true,
  'Documents verified'
);
```

## Reject

```sql
select public.admin_review_partner(
  '<driver_uuid>'::uuid,
  false,
  'Licence photo unclear. Please re-upload.'
);
```

Rejected partners see the reason in the app and can resubmit.

## OTP testing without SMS

```sql
alter database postgres set app.settings.partner_otp_debug = 'true';
```

Then `request_partner_phone_otp` returns `debug_otp` so you can verify in the app.
Wire MSG91/Twilio later to send the SMS for real.
