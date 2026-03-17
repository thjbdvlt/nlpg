alter table sent
    add constraint sent_textid_fkey;

foreign key (string)
references string (id);
