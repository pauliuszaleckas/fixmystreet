use utf8;
package FixMyStreet::DB::Result::Contact;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->load_components("FilterColumn", "InflateColumn::DateTime", "EncodedColumn");
__PACKAGE__->table("contacts");
__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "contacts_id_seq",
  },
  "body_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "category",
  { data_type => "text", default_value => "Other", is_nullable => 0 },
  "email",
  { data_type => "text", is_nullable => 0 },
  "confirmed",
  { data_type => "boolean", is_nullable => 0 },
  "deleted",
  { data_type => "boolean", is_nullable => 0 },
  "editor",
  { data_type => "text", is_nullable => 0 },
  "whenedited",
  { data_type => "timestamp", is_nullable => 0 },
  "note",
  { data_type => "text", is_nullable => 0 },
  "extra",
  { data_type => "text", is_nullable => 1 },
  "non_public",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "endpoint",
  { data_type => "text", is_nullable => 1 },
  "jurisdiction",
  { data_type => "text", default_value => "", is_nullable => 1 },
  "api_key",
  { data_type => "text", default_value => "", is_nullable => 1 },
  "send_method",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->add_unique_constraint("contacts_body_id_category_idx", ["body_id", "category"]);
__PACKAGE__->belongs_to(
  "body",
  "FixMyStreet::DB::Result::Body",
  { id => "body_id" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07017 @ 2012-12-13 12:34:33
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:imXq3EtrC0FrQwj+E2xfBw

__PACKAGE__->filter_column(
    extra => {
        filter_from_storage => sub {
            my $self = shift;
            my $ser  = shift;
            return undef unless defined $ser;
            my $h = new IO::String($ser);
            return RABX::wire_rd($h);
        },
        filter_to_storage => sub {
            my $self = shift;
            my $data = shift;
            my $ser  = '';
            my $h    = new IO::String($ser);
            RABX::wire_wr( $data, $h );
            return $ser;
        },
    }
);

1;
