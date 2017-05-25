package MediaWords::DBI::Auth::ChangePassword;

#
# User password changing helpers (when password is known)
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use POSIX qw(strftime);

use MediaWords::DBI::Auth::Login;
use MediaWords::DBI::Auth::Password;
use MediaWords::Util::Mail;

sub _send_password_changed_email($)
{
    my $email = shift;

    # Send email
    my $now           = strftime( "%a, %d %b %Y %H:%M:%S %z", localtime( time() ) );
    my $email_subject = 'Your password has been changed';
    my $email_message = <<"EOF";
Your Media Cloud password has been changed on $now.

If you made this change, no need to reply - you're all set.

If you did not request this change, please contact Media Cloud support at
www.mediacloud.org.
EOF

    unless ( MediaWords::Util::Mail::send( $email, $email_subject, $email_message ) )
    {
        die 'The password has been changed, but I was unable to send an email notifying you about the change.';
    }
}

# Change password; die()s on failure
sub change_password($$$$;$)
{
    my ( $db, $email, $password_new, $password_new_repeat, $do_not_inform_via_email ) = @_;

    my $password_validation_message =
      MediaWords::DBI::Auth::Password::validate_new_password( $email, $password_new, $password_new_repeat );
    if ( $password_validation_message )
    {
        die "Unable to change password: $password_validation_message";
    }

    # Hash + validate the password
    my $password_new_hash;
    eval { $password_new_hash = MediaWords::DBI::Auth::Password::generate_secure_hash( $password_new ); };
    if ( $@ or ( !$password_new_hash ) )
    {
        die "Unable to hash a new password: $@";
    }

    # Set the password hash
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET password_hash = ?, active = true
        WHERE email = ?
SQL
        $password_new_hash, $email
    );

    unless ( $do_not_inform_via_email )
    {
        _send_password_changed_email( $email );
    }
}

# Change password by entering old password; die()s on error
sub change_password_with_old_password($$$$$)
{
    my ( $db, $email, $password_old, $password_new, $password_new_repeat ) = @_;

    unless ( $password_old )
    {
        die 'To change the password, please enter an old ' . 'password and then repeat the new password twice.';
    }

    if ( $password_old eq $password_new )
    {
        die 'Old and new passwords are the same.';
    }

    # Validate old password; fetch the hash from the database again because
    # that hash might be outdated (e.g. if the password has been changed
    # already)
    my $db_password_old = $db->query(
        <<"SQL",
        SELECT auth_users_id,
               email,
               password_hash
        FROM auth_users
        WHERE email = ?
        LIMIT 1
SQL
        $email
    )->hash;

    if ( !( ref( $db_password_old ) eq ref( {} ) and $db_password_old->{ auth_users_id } ) )
    {
        die 'Unable to find the user in the database.';
    }
    $db_password_old = $db_password_old->{ password_hash };

    # Validate the password
    my $user;
    eval { $user = MediaWords::DBI::Auth::Login::login_with_email_password( $db, $email, $password_old ); };
    if ( $@ or ( !$user ) )
    {
        die "Old password is incorrect: $@";
    }

    # Execute the change
    eval { change_password( $db, $email, $password_new, $password_new_repeat ); };
    if ( $@ )
    {
        my $error_message = "Unable to change password: $@";
        die $error_message;
    }
}

# Change password with a password token sent by email; die()s on error
sub change_password_with_reset_token($$$$$)
{
    my ( $db, $email, $password_reset_token, $password_new, $password_new_repeat ) = @_;

    unless ( $password_reset_token )
    {
        die 'Password reset token is empty.';
    }

    # Validate the token once more (was pre-validated in controller)
    unless ( MediaWords::DBI::Auth::Password::password_reset_token_is_valid( $db, $email, $password_reset_token ) )
    {
        die 'Password reset token is invalid.';
    }

    # Execute the change
    eval { change_password( $db, $email, $password_new, $password_new_repeat ); };
    if ( $@ )
    {
        my $error_message = "Unable to change password: $@";
        die $error_message;
    }

    # Unset the password reset token
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET password_reset_token_hash = NULL
        WHERE email = ?
SQL
        $email
    );
}

1;
