open Batteries
open Stdint
open Dessser
module T = DessserTypes
module E = DessserExpressions
open E.Ops

type sexpr_config =
  { list_prefix_length : bool }

let default_config =
  { list_prefix_length = true }

module Ser : SER with type config = sexpr_config =
struct
  type config = sexpr_config

  type state = config

  let ptr _vtyp = T.dataptr

  let start ?(config=default_config) _v p = config, p

  let stop _conf p = p

  type ser = state -> T.maybe_nullable -> T.path -> E.t -> E.t -> E.t

  let sfloat _conf _ _ v p =
    write_bytes p (bytes_of_string (string_of_float v))

  let sbytes v p =
    let quo = byte_of_const_char '"' in
    let p = write_byte p quo in
    (* FIXME: escape double quotes: *)
    let p = write_bytes p v in
    write_byte p quo

  let sstring _conf _ _ v p = sbytes (bytes_of_string v) p
  let schar _conf _ _ v p = sbytes (bytes_of_string (string_of_char v)) p

  let sbool _conf _ _ v p =
    write_byte p (if_ v (byte_of_const_char 'T') (byte_of_const_char 'F'))

  let si _conf _ _ v p =
    write_bytes p (bytes_of_string (string_of_int v))

  let si8 = si
  let si16 = si
  let si24 = si
  let si32 = si
  let si40 = si
  let si48 = si
  let si56 = si
  let si64 = si
  let si128 = si
  let su8 = si
  let su16 = si
  let su24 = si
  let su32 = si
  let su40 = si
  let su48 = si
  let su56 = si
  let su64 = si
  let su128 = si

  (* Could also write the field names with the value in a pair... *)
  let tup_opn _conf _ _ _ p =
    write_byte p (byte_of_const_char '(')

  let tup_cls _conf _ _ p =
    write_byte p (byte_of_const_char ')')

  let tup_sep _conf _ _ p =
    write_byte p (byte_of_const_char ' ')

  let rec_opn _conf _ _ _ p =
    write_byte p (byte_of_const_char '(')

  let rec_cls _conf _ _ p =
    write_byte p (byte_of_const_char ')')

  let rec_sep _conf _ _ p =
    write_byte p (byte_of_const_char ' ')

  let sum_opn st mn0 path mos lbl p =
    let p = tup_opn st mn0 path mos p in
    let p = su16 st mn0 path lbl p in
    tup_sep st mn0 path p

  let sum_cls st mn0 path p =
    tup_cls st mn0 path p

  let vec_opn _conf _ _ _ _ p =
    write_byte p (byte_of_const_char '(')

  let vec_cls _conf _ _ p =
    write_byte p (byte_of_const_char ')')

  let vec_sep _conf _ _ p =
    write_byte p (byte_of_const_char ' ')

  let list_opn conf vtyp0 path _ n p =
    let p =
      if conf.list_prefix_length then
        match n with
        | Some n ->
            let p = su32 conf vtyp0 path n p in
            write_byte p (byte_of_const_char ' ')
        | None ->
            failwith "SExpr.Ser needs list length upfront"
      else
        p in
    write_byte p (byte_of_const_char '(')

  let list_cls _conf _ _ p =
    write_byte p (byte_of_const_char ')')

  let list_sep _conf _ _ p =
    write_byte p (byte_of_const_char ' ')

  let nullable _conf _ _ p = p

  let snull _t _conf _ _ p =
    write_dword LittleEndian p (dword (Uint32.of_int32 0x6c_6c_75_6el))

  let snotnull _t _conf _ _ p = p

  type ssizer = T.maybe_nullable -> T.path -> E.t -> ssize
  let todo_ssize () = failwith "TODO: ssize for SExpr"
  let ssize_of_float _ _ _ = todo_ssize ()
  let ssize_of_string _ _ _ = todo_ssize ()
  let ssize_of_bool _ _ _ = todo_ssize ()
  let ssize_of_char _ _ _ = todo_ssize ()
  let ssize_of_i8 _ _ _ = todo_ssize ()
  let ssize_of_i16 _ _ _ = todo_ssize ()
  let ssize_of_i24 _ _ _ = todo_ssize ()
  let ssize_of_i32 _ _ _ = todo_ssize ()
  let ssize_of_i40 _ _ _ = todo_ssize ()
  let ssize_of_i48 _ _ _ = todo_ssize ()
  let ssize_of_i56 _ _ _ = todo_ssize ()
  let ssize_of_i64 _ _ _ = todo_ssize ()
  let ssize_of_i128 _ _ _ = todo_ssize ()
  let ssize_of_u8 _ _ _ = todo_ssize ()
  let ssize_of_u16 _ _ _ = todo_ssize ()
  let ssize_of_u24 _ _ _ = todo_ssize ()
  let ssize_of_u32 _ _ _ = todo_ssize ()
  let ssize_of_u40 _ _ _ = todo_ssize ()
  let ssize_of_u48 _ _ _ = todo_ssize ()
  let ssize_of_u56 _ _ _ = todo_ssize ()
  let ssize_of_u64 _ _ _ = todo_ssize ()
  let ssize_of_u128 _ _ _ = todo_ssize ()
  let ssize_of_tup _ _ _ = todo_ssize ()
  let ssize_of_rec _ _ _ = todo_ssize ()
  let ssize_of_sum _ _ _ = todo_ssize ()
  let ssize_of_vec _ _ _ = todo_ssize ()
  let ssize_of_list _ _ _ = todo_ssize ()
  let ssize_of_null _ _ = todo_ssize ()
end

module Des : DES with type config = sexpr_config =
struct
  type config = sexpr_config

  type state = config

  let ptr _vtyp = T.dataptr

  let start ?(config=default_config) _mn p = config, p

  let stop _conf p = p

  type des = state -> T.maybe_nullable -> T.path -> E.t -> E.t

  let skip n p = data_ptr_add p (size n)

  let skip1 = skip 1

  let tup_cls _conf _ _ p = skip1 p

  let tup_sep _conf _ _ p = skip1 p

  let dfloat _conf _ _ p =
    float_of_ptr p

  let dbool _conf _ _ p =
    E.with_sploded_pair "dbool" (read_byte p) (fun b p ->
      pair (eq b (byte_of_const_char 'T')) p)

  (* Read a string of bytes and process them through [conv]: *)
  let dbytes conv p =
    (* Skip the double-quote: *)
    let p = skip1 p in
    (* Read up to next double-quote: *)
    (* FIXME: handle escaping backslash! *)
    let cond = E.func1 T.byte (fun _l b -> not_ (eq b (byte_of_const_char '"')))
    and init = bytes_of_string (string "")
    and reduce = E.func2 T.bytes T.byte (fun _l -> append_byte) in
    let str_p = read_while ~cond ~reduce ~init ~pos:p in
    E.with_sploded_pair "dbytes" str_p (fun str p ->
      (* Skip the closing double-quote: *)
      let p = skip1 p in
      pair (conv str) p)

  let dstring _conf _ _ p = dbytes string_of_bytes p
  (* Chars are encoded as single char strings *)
  let dchar _conf _ _ p = dbytes (char_of_string % string_of_bytes) p

  let di8 _conf _ _ p = i8_of_ptr p
  let du8 _conf _ _ p = u8_of_ptr p
  let di16 _conf _ _ p = i16_of_ptr p
  let du16 _conf _ _ p = u16_of_ptr p
  let di24 _conf _ _ p = i24_of_ptr p
  let du24 _conf _ _ p = u24_of_ptr p
  let di32 _conf _ _ p = i32_of_ptr p
  let du32 _conf _ _ p = u32_of_ptr p
  let di40 _conf _ _ p = i40_of_ptr p
  let du40 _conf _ _ p = u40_of_ptr p
  let di48 _conf _ _ p = i48_of_ptr p
  let du48 _conf _ _ p = u48_of_ptr p
  let di56 _conf _ _ p = i56_of_ptr p
  let du56 _conf _ _ p = u56_of_ptr p
  let di64 _conf _ _ p = i64_of_ptr p
  let du64 _conf _ _ p = u64_of_ptr p
  let di128 _conf _ _ p = i128_of_ptr p
  let du128 _conf _ _ p = u128_of_ptr p

  let tup_opn _conf _ _ _ p = skip1 p

  let tup_cls _conf _ _ p = skip1 p

  let tup_sep _conf _ _ p = skip1 p

  let rec_opn _conf _ _ _ p = skip1 p

  let rec_cls _conf _ _ p = skip1 p

  let rec_sep _conf _ _ p = skip1 p

  (* Sums are encoded as a pair of numeric label and value: *)
  let sum_opn st mn0 path mos p =
    let p = tup_opn st mn0 path mos p in
    let c_p = du16 st mn0 path p in
    E.with_sploded_pair "sum_opn" c_p (fun c p ->
      let p = tup_sep st mn0 path p in
      pair c p)

  let sum_cls st mn0 path p =
    tup_cls st mn0 path p

  let vec_opn _conf _ _ _ _ p = skip1 p

  let vec_cls _conf _ _ p = skip1 p

  let vec_sep _conf _ _ p = skip1 p

  let list_opn conf =
    if conf.list_prefix_length then
      KnownSize (fun vtyp0 path _ p ->
        E.with_sploded_pair "list_opn" (du32 conf vtyp0 path p) (fun v p ->
          pair v (skip 2 p)))
    else
      UnknownSize (
        (fun _ _ _ p -> skip1 p),
        (fun _ _ p ->
          eq (peek_byte p (size 0)) (byte_of_const_char ')')))

  let list_cls _conf _ _ p = skip1 p

  let list_sep _conf _ _ p = skip1 p

  let is_null _conf _ _ p =
    (* null *)
    and_ (and_ (eq (peek_byte p (size 0)) (byte (Uint8.of_int 0x6e)))
               (and_ (eq (peek_byte p (size 1)) (byte (Uint8.of_int 0x75)))
                     (and_ (eq (peek_byte p (size 2)) (byte (Uint8.of_int 0x6c)))
                           (eq (peek_byte p (size 3)) (byte (Uint8.of_int 0x6c))))))
         (or_ (eq (rem_size p) (size 4))
              (let_ "b" (peek_byte p (size 4))
                    ~in_:(or_ (eq (identifier "b") (byte_of_const_char ' '))
                              (eq (identifier "b") (byte_of_const_char ')')))))

  let dnull _t _conf _ _ p = skip 4 p

  let dnotnull _t _conf _ _ p = p
end