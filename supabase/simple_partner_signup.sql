-- Interim partner signup: no OTP / documents / admin review.
-- Run once in Supabase SQL Editor so new accounts can go online immediately.
-- Safe to run again. Revert when SMS + document verification is added.

create or replace function public.handle_new_driver()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.raw_user_meta_data->>'role' = 'driver' then
    insert into public.drivers (
      id, full_name, phone, email,
      phone_verified, verification_status
    )
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'full_name', 'Partner'),
      coalesce(new.raw_user_meta_data->>'phone', ''),
      new.email,
      true,
      'approved'
    )
    on conflict (id) do update
      set full_name = excluded.full_name,
          phone = excluded.phone,
          email = excluded.email,
          phone_verified = true,
          verification_status = 'approved',
          updated_at = now();
  end if;
  return new;
end;
$$;
