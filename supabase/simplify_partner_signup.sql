-- Simple partner signup: no OTP and no admin approval before going online.
-- Run once in the Supabase SQL editor.

create or replace function public.drivers_require_approval()
returns trigger
language plpgsql
as $$
begin
  return new;
end;
$$;

-- Existing partners stuck on pending/draft can go online too.
update public.drivers
set verification_status = 'approved',
    phone_verified = true,
    updated_at = now()
where coalesce(verification_status, 'draft') <> 'approved'
   or coalesce(phone_verified, false) is not true;
