-- New accounts must use a UiTM student address (@student.uitm.edu.my),
-- whether they sign up with email/password or Google. Enforced here so
-- it can't be bypassed by calling the Auth API directly; the app checks
-- too, for a friendlier message.
--
-- BEFORE INSERT only: accounts that already exist (e.g. the owner's
-- gmail) are untouched and keep signing in normally.
--
-- Escape hatch for staff/test accounts: create the user from the
-- dashboard or Admin API with app_metadata {"allow_non_student": true}.
--
-- A rejected Google sign-up returns to the app with
-- error_description = "Database error saving new user"; the login
-- screen maps that to the student-email message.

create or replace function public.enforce_student_email_signup()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if coalesce((new.raw_app_meta_data ->> 'allow_non_student')::boolean, false) then
    return new;
  end if;

  if lower(coalesce(new.email, '')) not like '%@student.uitm.edu.my' then
    raise exception 'Sign-up requires a @student.uitm.edu.my email address'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_student_email_signup on auth.users;
create trigger trg_enforce_student_email_signup
before insert on auth.users
for each row execute function public.enforce_student_email_signup();
