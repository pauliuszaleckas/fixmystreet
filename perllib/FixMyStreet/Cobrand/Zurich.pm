package FixMyStreet::Cobrand::Zurich;
use base 'FixMyStreet::Cobrand::Default';

use DateTime;
use POSIX qw(strcoll);

use strict;
use warnings;

sub shorten_recency_if_new_greater_than_fixed {
    return 0;
}

sub pin_colour {
    my ( $self, $p, $context ) = @_;
    return 'green' if $p->is_fixed || $p->is_closed;
    return 'red' if $p->state eq 'unconfirmed' || $p->state eq 'confirmed';
    return 'yellow';
}

# This isn't used
sub find_closest {
    my ( $self, $latitude, $longitude, $problem ) = @_;
    return '';
}

sub enter_postcode_text {
    my ( $self ) = @_;
    return _('Enter a Z&uuml;rich street name');
}

sub example_places {
    return [ 'Langstrasse', 'Basteiplatz' ];
}

sub languages { [ 'de-ch,Deutsch,de_CH', 'en-gb,English,en_GB' ] };

# If lat/lon are in the URI, we must have zoom as well, otherwise OpenLayers defaults to 0.
sub uri {
    my ( $self, $uri ) = @_;

    $uri->query_param( zoom => 6 )
      if $uri->query_param('lat') && !$uri->query_param('zoom');
    return $uri;
}

sub prettify_dt {
    my $self = shift;
    my $dt = shift;

    return Utils::prettify_dt( $dt, 'zurich' );
}

sub problem_as_hashref {
    my $self = shift;
    my $problem = shift;
    my $ctx = shift;

    my $hashref = $problem->as_hashref( $ctx );

    if ( $problem->state eq 'unconfirmed' ) {
        for my $var ( qw( photo detail state state_t is_fixed meta ) ) {
            delete $hashref->{ $var };
        }
        $hashref->{detail} = _('This report is awaiting moderation.');
        $hashref->{state} = 'submitted';
        $hashref->{state_t} = _('Submitted');
    } else {
        if ( $problem->state eq 'confirmed' ) {
            $hashref->{state} = 'open';
            $hashref->{state_t} = _('Open');
        } elsif ( $problem->is_fixed ) {
            $hashref->{state} = 'closed';
            $hashref->{state_t} = _('Closed');
        } elsif ( $problem->state eq 'in progress' || $problem->state eq 'planned' ) {
            $hashref->{state} = 'in progress';
            $hashref->{state_t} = _('In progress');
        }
    }

    return $hashref;
}

sub updates_as_hashref {
    my $self = shift;
    my $problem = shift;
    my $ctx = shift;

    my $hashref = {};

    if ( $problem->state eq 'fixed - council' || $problem->state eq 'closed' ) {
        $hashref->{update_pp} = $self->prettify_dt( $problem->lastupdate );

        if ( $problem->state eq 'fixed - council' ) {
            $hashref->{details} = FixMyStreet::App::View::Web->add_links( $ctx, $problem->extra->{public_response} );
        } elsif ( $problem->state eq 'closed' ) {
            $hashref->{details} = sprintf( _('Assigned to %s'), $problem->body($ctx)->name );
        }
    }

    return $hashref;
}

sub remove_redundant_areas {
    my $self = shift;
    my $all_areas = shift;

    # Remove all except Zurich
    foreach (keys %$all_areas) {
        delete $all_areas->{$_} unless $_ eq 274456;
    }
}

sub show_unconfirmed_reports {
    1;
}

sub get_body_sender {
    my ( $self, $body, $category ) = @_;
    return { method => 'Zurich' };
}

# Report overdue functions

my %public_holidays = map { $_ => 1 } (
    '2013-01-01', '2013-01-02', '2013-03-29', '2013-04-01',
    '2013-04-15', '2013-05-01', '2013-05-09', '2013-05-20',
    '2013-08-01', '2013-09-09', '2013-12-25', '2013-12-26',
    '2014-01-01', '2014-01-02', '2014-04-18', '2014-04-21',
    '2014-04-28', '2014-05-01', '2014-05-29', '2014-06-09',
    '2014-08-01', '2014-09-15', '2014-12-25', '2014-12-26',
);

sub is_public_holiday {
    my $dt = shift;
    return $public_holidays{$dt->ymd};
}

sub is_weekend {
    my $dt = shift;
    return $dt->dow > 5;
}

sub add_days {
    my ( $dt, $days ) = @_;
    $dt = $dt->clone;
    while ( $days > 0 ) {
        $dt->add ( days => 1 );
        next if is_public_holiday($dt) or is_weekend($dt);
        $days--;
    }
    return $dt;
}

sub sub_days {
    my ( $dt, $days ) = @_;
    $dt = $dt->clone;
    while ( $days > 0 ) {
        $dt->subtract ( days => 1 );
        next if is_public_holiday($dt) or is_weekend($dt);
        $days--;
    }
    return $dt;
}

sub overdue {
    my ( $self, $problem ) = @_;

    my $w = $problem->whensent;
    return 0 unless $w;

    if ( $problem->state eq 'unconfirmed' || $problem->state eq 'confirmed' ) {
        # One working day
        $w = add_days( $w, 1 );
        return $w < DateTime->now() ? 1 : 0;
    } elsif ( $problem->state eq 'in progress' ) {
        # Five working days
        $w = add_days( $w, 5 );
        return $w < DateTime->now() ? 1 : 0;
    } else {
        return 0;
    }
}

sub email_indent { ''; }

# Specific administrative displays

sub admin_pages {
    my $self = shift;
    my $c = $self->{c};

    my $type = $c->stash->{admin_type};
    my $pages = {
        'summary' => [_('Summary'), 0],
        'reports' => [_('Reports'), 2],
        'report_edit' => [undef, undef],
        'update_edit' => [undef, undef],
    };
    return $pages if $type eq 'sdm';

    $pages = { %$pages,
        'bodies' => [_('Bodies'), 1],
        'body' => [undef, undef],
        'body_edit' => [undef, undef],
    };
    return $pages if $type eq 'dm';

    $pages = { %$pages,
        'users' => [_('Users'), 3],
        'stats' => [_('Stats'), 4],
        'user_edit' => [undef, undef],
    };
    return $pages if $type eq 'super';
}

sub admin_type {
    my $self = shift;
    my $c = $self->{c};
    my $body = $c->user->from_body;
    $c->stash->{body} = $body;

    my $parent = $body->parent;
    my $children = $body->bodies->count;

    my $type;
    if (!$parent) {
        $type = 'super';
    } elsif ($parent && $children) {
        $type = 'dm';
    } elsif ($parent) {
        $type = 'sdm';
    }

    $c->stash->{admin_type} = $type;
    return $type;
}

sub admin {
    my $self = shift;
    my $c = $self->{c};
    my $type = $c->stash->{admin_type};

    if ($type eq 'dm') {
        $c->stash->{template} = 'admin/index-dm.html';

        my $body = $c->stash->{body};
        my @children = map { $_->id } $body->bodies->all;
        my @all = (@children, $body->id);

        my $order = $c->req->params->{o} || 'created';
        my $dir = defined $c->req->params->{d} ? $c->req->params->{d} : 1;
        $c->stash->{order} = $order;
        $c->stash->{dir} = $dir;
        $order .= ' desc' if $dir;

        # XXX No multiples or missing bodies
        $c->stash->{unconfirmed} = $c->cobrand->problems->search({
            state => [ 'unconfirmed', 'confirmed' ],
            bodies_str => $c->stash->{body}->id,
        }, {
            order_by => $order,
        });
        $c->stash->{approval} = $c->cobrand->problems->search({
            state => 'planned',
            bodies_str => $c->stash->{body}->id,
        }, {
            order_by => $order,
        });

        my $page = $c->req->params->{p} || 1;
        $c->stash->{other} = $c->cobrand->problems->search({
            state => { -not_in => [ 'unconfirmed', 'confirmed', 'planned' ] },
            bodies_str => \@all,
        }, {
            order_by => $order,
        })->page( $page );
        $c->stash->{pager} = $c->stash->{other}->pager;

    } elsif ($type eq 'sdm') {
        $c->stash->{template} = 'admin/index-sdm.html';

        my $body = $c->stash->{body};

        my $order = $c->req->params->{o} || 'created';
        my $dir = defined $c->req->params->{d} ? $c->req->params->{d} : 1;
        $c->stash->{order} = $order;
        $c->stash->{dir} = $dir;
        $order .= ' desc' if $dir;

        # XXX No multiples or missing bodies
        $c->stash->{reports_new} = $c->cobrand->problems->search( {
            state => 'in progress',
            bodies_str => $body->id,
        }, {
            order_by => $order
        } );
        $c->stash->{reports_unpublished} = $c->cobrand->problems->search( {
            state => 'planned',
            bodies_str => $body->parent->id,
        }, {
            order_by => $order
        } );

        my $page = $c->req->params->{p} || 1;
        $c->stash->{reports_published} = $c->cobrand->problems->search( {
            state => 'fixed - council',
            bodies_str => $body->parent->id,
        }, {
            order_by => $order
        } )->page( $page );
        $c->stash->{pager} = $c->stash->{reports_published}->pager;
    }
}

sub admin_report_edit {
    my $self = shift;
    my $c = $self->{c};
    my $type = $c->stash->{admin_type};

    my $problem = $c->stash->{problem};
    my $body = $c->stash->{body};

    if ($type ne 'super') {
        my %allowed_bodies = map { $_->id => 1 } ( $body->bodies->all, $body );
        $c->detach( '/page_error_404_not_found' )
          unless $allowed_bodies{$problem->bodies_str};
    }

    if ($type eq 'super') {

        my @bodies = $c->model('DB::Body')->all();
        @bodies = sort { strcoll($a->name, $b->name) } @bodies;
        $c->stash->{bodies} = \@bodies;

        # Can change category to any other
        my @categories = $c->model('DB::Contact')->not_deleted->all;
        $c->stash->{categories} = [ map { $_->category } @categories ];

    } elsif ($type eq 'dm') {

        # Can assign to:
        my @bodies = $c->model('DB::Body')->search( [
            { 'me.parent' => $body->parent->id }, # Other DMs on the same level
            { 'me.parent' => $body->id }, # Their subdivisions
            { 'me.parent' => undef, 'bodies.id' => undef }, # External bodies
        ], { join => 'bodies', distinct => 1 } );
        @bodies = sort { strcoll($a->name, $b->name) } @bodies;
        $c->stash->{bodies} = \@bodies;

        # Can change category to any other
        my @categories = $c->model('DB::Contact')->not_deleted->all;
        $c->stash->{categories} = [ map { $_->category } @categories ];

    }

    # Problem updates upon submission
    if ( ($type eq 'super' || $type eq 'dm') && $c->req->param('submit') ) {
        $c->forward('check_token');

        # Predefine the hash so it's there for lookups
        # XXX Note you need to shallow copy each time you set it, due to a bug? in FilterColumn.
        my $extra = $problem->extra || {};
        $extra->{internal_notes} = $c->req->param('internal_notes');
        $extra->{publish_photo} = $c->req->params->{publish_photo} || 0;
        $extra->{third_personal} = $c->req->params->{third_personal} || 0;
        # Make sure we have a copy of the original detail field
        $extra->{original_detail} = $problem->detail if !$extra->{original_detail} && $c->req->params->{detail} && $problem->detail ne $c->req->params->{detail};

        # Workflow things
        my $redirect = 0;
        my $new_cat = $c->req->params->{category};
        if ( $new_cat && $new_cat ne $problem->category ) {
            my $cat = $c->model('DB::Contact')->search( { category => $c->req->params->{category} } )->first;
            $problem->category( $new_cat );
            $problem->external_body( undef );
            $problem->bodies_str( $cat->body_id );
            $problem->whensent( undef );
            $extra->{changed_category} = 1;
            $redirect = 1 if $cat->body_id ne $body->id;
        } elsif ( my $subdiv = $c->req->params->{body_subdivision} ) {
            $extra->{moderated_overdue} = $self->overdue( $problem );
            $problem->state( 'in progress' );
            $problem->external_body( undef );
            $problem->bodies_str( $subdiv );
            $problem->whensent( undef );
            $redirect = 1;
        } elsif ( my $external = $c->req->params->{body_external} ) {
            $extra->{moderated_overdue} = $self->overdue( $problem );
            $problem->state( 'closed' );
            $problem->external_body( $external );
            $problem->whensent( undef );
            _admin_send_email( $c, 'problem-external.txt', $problem );
            $redirect = 1;
        } else {
            $problem->state( $c->req->params->{state} ) if $c->req->params->{state};
            if ( $problem->state eq 'hidden' ) {
                _admin_send_email( $c, 'problem-rejected.txt', $problem );
            }
        }

        $problem->extra( { %$extra } );
        $problem->title( $c->req->param('title') );
        $problem->detail( $c->req->param('detail') );
        $problem->latitude( $c->req->param('latitude') );
        $problem->longitude( $c->req->param('longitude') );

        # Final, public, Update from DM
        if (my $update = $c->req->param('status_update')) {
            $extra->{public_response} = $update;
            $problem->extra( { %$extra } );
            if ($c->req->params->{publish_response}) {
                $problem->state( 'fixed - council' );
                _admin_send_email( $c, 'problem-closed.txt', $problem );
            }
        }

        $problem->lastupdate( \'ms_current_timestamp()' );
        $problem->update;

        $c->stash->{status_message} =
          '<p><em>' . _('Updated!') . '</em></p>';

        # do this here otherwise lastupdate and confirmed times
        # do not display correctly
        $problem->discard_changes;

        if ( $redirect ) {
            $c->detach('index');
        }

        $c->stash->{updates} = [ $c->model('DB::Comment')
          ->search( { problem_id => $problem->id }, { order_by => 'created' } )
          ->all ];

        return 1;
    }

    if ($type eq 'sdm') {

        # Has cut-down edit template for adding update and sending back up only
        $c->stash->{template} = 'admin/report_edit-sdm.html';

        if ($c->req->param('send_back')) {
            $c->forward('check_token');

            $problem->bodies_str( $body->parent->id );
            $problem->state( 'confirmed' );
            $problem->update;
            # log here
            $c->res->redirect( '/admin/summary' );

        } elsif ($c->req->param('submit')) {
            $c->forward('check_token');

            my $db_update = 0;
            if ( $c->req->param('latitude') != $problem->latitude || $c->req->param('longitude') != $problem->longitude ) {
                $problem->latitude( $c->req->param('latitude') );
                $problem->longitude( $c->req->param('longitude') );
                $db_update = 1;
            }

            my $extra = $problem->extra || {};
            $extra->{internal_notes} ||= '';
            if ($c->req->param('internal_notes') && $c->req->param('internal_notes') ne $extra->{internal_notes}) {
                $extra->{internal_notes} = $c->req->param('internal_notes');
                $problem->extra( { %$extra } );
                $db_update = 1;
            }

            $problem->update if $db_update;

            # Add new update from status_update
            if (my $update = $c->req->param('status_update')) {
                FixMyStreet::App->model('DB::Comment')->create( {
                    text => $update,
                    user => $c->user->obj,
                    state => 'unconfirmed',
                    problem => $problem,
                    mark_fixed => 0,
                    problem_state => 'fixed - council',
                    anonymous => 1,
                } );
            }

            $c->stash->{status_message} = '<p><em>' . _('Updated!') . '</em></p>';

            # If they clicked the no more updates button, we're done.
            if ($c->req->param('no_more_updates')) {
                $problem->bodies_str( $body->parent->id );
                $problem->whensent( undef );
                my $extra = $problem->extra || {};
                $extra->{subdiv_overdue} = $self->overdue( $problem );
                $problem->extra( { %$extra } );
                $problem->state( 'planned' );
                $problem->update;
                $c->res->redirect( '/admin/summary' );
            }
        }

        $c->stash->{updates} = [ $c->model('DB::Comment')
            ->search( { problem_id => $problem->id }, { order_by => 'created' } )
            ->all ];

        return 1;

    }

    return 0;

}

sub _admin_send_email {
    my ( $c, $template, $problem ) = @_;

    return unless $problem->extra && $problem->extra->{email_confirmed};

    my $to = $problem->name
        ? [ $problem->user->email, $problem->name ]
        : $problem->user->email;

    # Similar to what SendReport::Zurich does to find address to send to
    my $body = ( values %{$problem->bodies} )[0];
    my $sender = $body->endpoint || $c->cobrand->contact_email;
    my $sender_name = $c->cobrand->contact_name; # $body->name?

    $c->send_email( $template, {
        to => [ $to ],
        url => $c->uri_for_email( $problem->url ),
        from => [ $sender, $sender_name ],
    } );
}

sub admin_fetch_all_bodies {
    my ( $self, @bodies ) = @_;

    sub tree_sort {
        my ( $level, $id, $sorted, $out ) = @_;

        my @sorted;
        my $array = $sorted->{$id};
        if ( $level == 0 ) {
            @sorted = sort {
                # Want Zurich itself at the top.
                return -1 if $sorted->{$a->id};
                return 1 if $sorted->{$b->id};
                # Otherwise, by name
                strcoll($a->name, $b->name)
            } @$array;
        } else {
            @sorted = sort { strcoll($a->name, $b->name) } @$array;
        }
        foreach ( @sorted ) {
            $_->api_key( $level ); # Misuse
            push @$out, $_;
            if ($sorted->{$_->id}) {
                tree_sort( $level+1, $_->id, $sorted, $out );
            }
        }
    }

    my %sorted;
    foreach (@bodies) {
        my $p = $_->parent ? $_->parent->id : 0;
        push @{$sorted{$p}}, $_;
    }

    my @out;
    tree_sort( 0, 0, \%sorted, \@out );
    return @out;
}

sub admin_stats {
    my $self = shift;
    my $c = $self->{c};

    my %date_params;
    my $ym = $c->req->params->{ym};
    my ($m, $y) = $ym =~ /^(\d+)\.(\d+)$/;
    $c->stash->{ym} = $ym;
    if ($y && $m) {
        $c->stash->{start_date} = DateTime->new( year => $y, month => $m, day => 1 );
        $c->stash->{end_date} = $c->stash->{start_date} + DateTime::Duration->new( months => 1 );
        $date_params{created} = { '>=', $c->stash->{start_date}, '<', $c->stash->{end_date} };
    }

    my %params = (
        %date_params,
        state => [ FixMyStreet::DB::Result::Problem->visible_states() ],
    );

    if ( $c->req->params->{export} ) {
        my $problems = $c->model('DB::Problem')->search( { %params }, { columns => [ 'id', 'created', 'latitude', 'longitude', 'cobrand', 'category' ] } );
        my $body = "ID,Created,E,N,Category\n";
        while (my $report = $problems->next) {
            $body .= join( ',', $report->id, $report->created, $report->local_coords, $report->category ) . "\n";
        }
        $c->res->content_type('text/csv; charset=utf-8');
        $c->res->body($body);
    }

    # Total reports (non-hidden)
    my $total = $c->model('DB::Problem')->search( \%params )->count;
    # Device for apps (iOS/Android)
    my $per_service = $c->model('DB::Problem')->search( \%params, {
        select   => [ 'service', { count => 'id' } ],
        as       => [ 'service', 'c' ],
        group_by => [ 'service' ],
    });
    # Reports solved
    my $solved = $c->model('DB::Problem')->search( { state => 'fixed - council', %date_params } )->count;
    # Reports marked as spam
    my $hidden = $c->model('DB::Problem')->search( { state => 'hidden', %date_params } )->count;
    # Reports assigned to third party
    my $closed = $c->model('DB::Problem')->search( { state => 'closed', %date_params } )->count;
    # Reports moderated within 1 day
    my $moderated = $c->model('DB::Problem')->search( { extra => { like => '%moderated_overdue,I1:0%' }, %params } )->count;
    # Reports solved within 5 days
    my $subdiv_dealtwith = $c->model('DB::Problem')->search( { extra => { like => '%subdiv_overdue,I1:0%' }, %params } )->count;
    # Reports per category
    my $per_category = $c->model('DB::Problem')->search( \%params, {
        select   => [ 'category', { count => 'id' } ],
        as       => [ 'category', 'c' ],
        group_by => [ 'category' ],
    });
    # How many reports have had their category changed by a DM (wrong category chosen by user)
    my $changed = $c->model('DB::Problem')->search( { extra => { like => '%changed_category,I1:1%' }, %params } )->count;
    # pictures taken
    my $pictures_taken = $c->model('DB::Problem')->search( { photo => { '!=', undef }, %params } )->count;
    # pictures published
    my $pictures_published = $c->model('DB::Problem')->search( { extra => { like => '%publish_photo,I1:1%' }, %params } )->count;
    # how many times was a telephone number provided
    # XXX => How many users have a telephone number stored
    # my $phone = $c->model('DB::User')->search( { phone => { '!=', undef } } )->count;
    # how many times was the email address confirmed
    my $email_confirmed = $c->model('DB::Problem')->search( { extra => { like => '%email_confirmed%' }, %params } )->count;
    # how many times was the name provided
    my $name = $c->model('DB::Problem')->search( { name => { '!=', '' }, %params } )->count;
    # how many times was the geolocation used vs. addresssearch
    # ?

    $c->stash(
        per_service => $per_service,
        per_category => $per_category,
        reports_total => $total,
        reports_solved => $solved,
        reports_spam => $hidden,
        reports_assigned => $closed,
        reports_moderated => $moderated,
        reports_dealtwith => $subdiv_dealtwith,
        reports_category_changed => $changed,
        pictures_taken => $pictures_taken,
        pictures_published => $pictures_published,
        #users_phone => $phone,
        email_confirmed => $email_confirmed,
        name_provided => $name,
        # GEO
    );

    return 1;
}

1;
