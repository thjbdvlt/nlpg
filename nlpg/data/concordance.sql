create or replace function public.concord (
    word_,
    integer default 50
)
    returns table (
            left_context text,
            pivot text,
            right_context text
)
    language sql
    as $function$
    select
        regexp_replace(substring(
                case when $1.idx < $2 then
                    lpad('', ($2 + 1) - $1.idx, ' ') || string.val
                else
                    string.val
                end, greatest ($1.idx - $2, 1), $2), '[\n\t]', ' ', 'g'),
        regexp_replace(substring(string.val, $1.idx, $1.len), '[\n\t]', ' ', 'g'),
        regexp_replace(substring(string.val, $1.idx + $1.len + 1, $2), '[\n\t]', ' ', 'g')
    from
        string
    where
        $1.string = string.id
$function$;
