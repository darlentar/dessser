(* Random genrator for types and expressions *)
open Batteries
open Stdint
open DessserTypes
open QCheck

(*
 * Random types generator
 *)

let mac_type_gen =
  Gen.sized (fun n _st ->
    match n mod 22 with
    | 0 -> TFloat
    | 1 -> TString
    | 2 -> TBool
    | 3 -> TChar
    | 4 -> TU8
    | 5 -> TU16
    | 6 -> TU24
    | 7 -> TU32
    | 8 -> TU40
    | 9 -> TU48
    | 10 -> TU56
    | 11 -> TU64
    | 12 -> TU128
    | 13 -> TI8
    | 14 -> TI16
    | 15 -> TI24
    | 16 -> TI32
    | 17 -> TI40
    | 18 -> TI48
    | 19 -> TI56
    | 20 -> TI64
    | 21 -> TI128
    | _ -> assert false)

let user_type_gen =
  (* This module is linked after DessserTypes and therefore is initialized after
   * it, so it is OK to get default user types now: *)
  let user_type_keys = Hashtbl.keys user_types |> Array.of_enum in
  Gen.(sized (fun n _st ->
    let k = user_type_keys.(n mod Array.length user_type_keys) in
    Hashtbl.find user_types k))

let tiny_int =
  Gen.int_range 1 10

let tiny_array gen =
  Gen.(array_size (int_range 1 5) gen)

let tiny_list gen =
  Gen.(list_size (int_range 1 5) gen)

let field_name_gen =
  let open Gen in
  let all_chars = "abcdefghijklmnopqrstuvwxyz" in
  let gen = map (fun n -> all_chars.[n mod String.length all_chars]) nat in
  string_size ~gen (int_range 4 6)

let let_name_gen = field_name_gen

let rec value_type_gen depth =
  let open Gen in
  if depth > 0 then
    let mn_gen = maybe_nullable_gen (depth - 1) in
    let lst =
      [ 4, map (fun mt -> Mac mt) mac_type_gen ;
        1, map (fun ut -> Usr ut) user_type_gen ;
        2, map2 (fun dim mn -> TVec (dim, mn)) (int_range 1 10) mn_gen ;
        2, map (fun mn -> TList mn) mn_gen ;
        2, map (fun mns -> TTup mns) (tiny_array mn_gen) ;
        2, map (fun fs -> TRec fs) (tiny_array (pair field_name_gen mn_gen)) ;
        1, map2 (fun k v -> TMap (k, v)) mn_gen mn_gen ] in
    frequency lst
  else
    map (fun mt -> Mac mt) mac_type_gen

and maybe_nullable_gen depth =
  Gen.(fix (fun _self depth ->
    map2 (fun b vt ->
      if b then Nullable vt else NotNullable vt
    ) bool (value_type_gen depth)
  ) depth)

let value_type_gen =
  Gen.(sized_size (int_bound 4) value_type_gen)

let maybe_nullable_gen =
  Gen.(sized_size (int_bound 4) maybe_nullable_gen)

let rec size_of_value_type = function
  | Mac _ | Usr _ -> 1
  | TVec (_, mn) | TList mn -> size_of_maybe_nullable mn
  | TTup typs ->
      Array.fold_left (fun s mn -> s + size_of_maybe_nullable mn) 0 typs
  | TRec typs ->
      Array.fold_left (fun s (_, mn) -> s + size_of_maybe_nullable mn) 0 typs
  | TMap (k, v) ->
      size_of_maybe_nullable k + size_of_maybe_nullable v

and size_of_maybe_nullable = function
  | Nullable vt | NotNullable vt -> size_of_value_type vt

let shrink_mac_type mt =
  let to_simplest =
    [ TString ; TFloat ;
      TI128 ; TU128 ; TI64 ; TU64 ; TI56 ; TU56 ; TI48 ; TU48 ; TI40 ; TU40 ;
      TI32 ; TU32 ; TI24 ; TU24 ; TI16 ; TU16 ; TI8 ; TU8 ; TChar ; TBool ] in
  let rec loop = function
    | [] -> Iter.empty
    | mt'::rest when mt' = mt ->
        if rest = [] then Iter.empty else Iter.of_list rest
    | _::rest ->
        loop rest in
  loop to_simplest

let rec shrink_value_type =
  let vt_of_mn = function NotNullable vt | Nullable vt -> vt
  in
  function
  | Mac mt ->
      (fun f ->
        shrink_mac_type mt (fun mt -> f (Mac mt)))
  | Usr _ ->
      Iter.empty
  | TVec (dim, mn) ->
      (fun f ->
        shrink_maybe_nullable mn (fun mn ->
          f (vt_of_mn mn) ;
          f (TVec (dim, mn))))
  | TList mn ->
      (fun f ->
        shrink_maybe_nullable mn (fun mn ->
          f (TList mn) ;
          f (vt_of_mn mn)))
  | TTup mns ->
      (fun f ->
        Array.iter (fun mn -> shrink_maybe_nullable mn (f % vt_of_mn)) mns ;
        let shrink_mns =
          Shrink.filter (fun mns -> Array.length mns > 1)
            (Shrink.array ~shrink:shrink_maybe_nullable) mns |>
          Iter.map (fun mns -> TTup mns) in
        shrink_mns f)
  | TRec mns ->
      (fun f ->
        Array.iter (fun (_, mn) -> shrink_maybe_nullable mn (f % vt_of_mn)) mns ;
        let shrink_mns =
          let shrink (fn, mn) =
            Iter.map (fun mn -> fn, mn) (shrink_maybe_nullable mn) in
          Shrink.filter (fun mns -> Array.length mns > 1)
            (Shrink.array ~shrink) mns |>
          Iter.map (fun mns -> TRec mns) in
        shrink_mns f)
  | TMap (k, v) ->
      (fun f ->
        shrink_maybe_nullable k (f % vt_of_mn) ;
        shrink_maybe_nullable v (f % vt_of_mn) ;
        let shrink_kv =
          (Shrink.pair shrink_maybe_nullable shrink_maybe_nullable) (k, v) |>
          Iter.map (fun (k, v) -> TMap (k, v)) in
        shrink_kv f)

and shrink_maybe_nullable = function
  | Nullable vt ->
      (fun f ->
        shrink_value_type vt (fun vt ->
          f (NotNullable vt) ;
          f (Nullable vt)))
  | NotNullable vt ->
      (fun f ->
        shrink_value_type vt (fun vt -> f (NotNullable vt)))

let value_type =
  let print = IO.to_string print_value_type
  and small = size_of_value_type
  and shrink = shrink_value_type in
  make ~print ~small ~shrink value_type_gen

let maybe_nullable =
  let print = IO.to_string print_maybe_nullable
  and small = size_of_maybe_nullable
  and shrink = shrink_maybe_nullable in
  make ~print ~small ~shrink maybe_nullable_gen

(*$inject
   open Batteries
   module T = DessserTypes
   module E = DessserExpressions *)

(*$Q maybe_nullable & ~count:10_000
  maybe_nullable (fun mn -> \
    let str = IO.to_string T.print_maybe_nullable mn in \
    let mn' = T.Parser.maybe_nullable_of_string str in \
    T.maybe_nullable_eq mn' mn)
*)

(*
 * Random expressions generator
 *)

open DessserExpressions
open Ops

let map4 f w x y z st = f (w st) (x st) (y st) (z st)
let map5 f v w x y z st = f (v st) (w st) (x st) (y st) (z st)

let endianness_gen =
  Gen.(map (function
    | true -> LittleEndian
    | false -> BigEndian
  ) bool)

let path_gen =
  Gen.(tiny_list tiny_int)

let get_next_fid =
  let next_fid = ref 0 in
  fun () ->
    incr next_fid ;
    !next_fid

(* Those with no arguments only *)
let e1_of_int n =
  let e1s =
    [| Dump ; Ignore ; IsNull ; ToNullable ; ToNotNullable ; StringOfFloat ;
       StringOfChar ; StringOfInt ; FloatOfString ; CharOfString ; U8OfString ;
       U16OfString ; U24OfString ; U32OfString ; U40OfString ; U48OfString ;
       U56OfString ; U64OfString ; U128OfString ; I8OfString ; I16OfString ;
       I24OfString ; I32OfString ; I40OfString ; I48OfString ; I56OfString ;
       I64OfString ; I128OfString ; ToU8 ; ToU16 ; ToU24 ; ToU32 ; ToU40 ;
       ToU48 ; ToU56 ; ToU64 ; ToU128 ; ToI8 ; ToI16 ; ToI24 ; ToI32 ; ToI40 ;
       ToI48 ; ToI56 ; ToI64 ; ToI128 ; LogNot ; FloatOfQWord ; QWordOfFloat ;
       U8OfByte ; ByteOfU8 ; U16OfWord ; WordOfU16 ; U32OfDWord ; DWordOfU32 ;
       U64OfQWord ; QWordOfU64 ; U128OfOWord ; OWordOfU128 ; U8OfChar ;
       CharOfU8 ; SizeOfU32 ; U32OfSize ; BitOfBool ; BoolOfBit ; U8OfBool ;
       BoolOfU8 ; StringLength ; StringOfBytes ; BytesOfString ; ListLength ;
       ReadByte ; DataPtrPush ; DataPtrPop ; RemSize ; Not ; DerefValuePtr ;
       Fst ; Snd |] in
  e1s.(n mod Array.length e1s)

let e2_of_int n =
  let e2s =
    [| Coalesce ; Gt ; Ge ; Eq ; Ne ; Add ; Sub ; Mul ; Div ; Rem ; LogAnd ;
       LogOr ; LogXor ; LeftShift ; RightShift ; AppendBytes ; AppendString ;
       TestBit ; ReadBytes ; PeekByte ; WriteByte ; WriteBytes ; PokeByte ;
       DataPtrAdd ; DataPtrSub ; And ; Or ; Pair ; MapPair |] in
  e2s.(n mod Array.length e2s)

let e3_of_int n =
  let e3s = [| SetBit ; BlitByte ; Choose ; LoopWhile ; LoopUntil |] in
  e3s.(n mod Array.length e3s)

let e4_of_int n =
  let e4s = [| ReadWhile ; Repeat |] in
  e4s.(n mod Array.length e4s)

let rec e0_gen l depth =
  let open Gen in
  let lst = [
    1, map null value_type_gen ;
    1, map Ops.float float ;
    1, map Ops.string small_string ;
    1, map Ops.bool bool ;
    1, map Ops.char char ;
    1, map Ops.u8 (int_bound 255) ;
    1, map Ops.u16 (int_bound 65535) ;
    1, map Ops.u24 (int_bound 16777215) ;
    1, map (Ops.u32 % Uint32.of_int) nat ;
    1, map (Ops.u40 % Uint40.of_int) nat ;
    1, map (Ops.u48 % Uint48.of_int) nat ;
    1, map (Ops.u56 % Uint56.of_int) nat ;
    1, map (Ops.u64 % Uint64.of_int) nat ;
    1, map (Ops.u128 % Uint128.of_int) nat ;
    1, map Ops.i8 (int_range (-128) 127) ;
    1, map Ops.i16 (int_range (-32768) 32767) ;
    1, map Ops.i24 (int_range (-8388608) 8388607) ;
    1, map (Ops.i32 % Int32.of_int) int ;
    1, map (Ops.i40 % Int64.of_int) int ;
    1, map (Ops.i48 % Int64.of_int) int ;
    1, map (Ops.i56 % Int64.of_int) int ;
    1, map (Ops.i64 % Int64.of_int) int ;
    1, map (Ops.i128 % Int128.of_int) int ;
    1, map Ops.bit bool ;
    1, map Ops.size small_nat ;
    1, map Ops.byte (int_bound 255) ;
    1, map Ops.word (int_bound 65535) ;
    1, map (Ops.dword % Uint32.of_int32) ui32 ;
    1, map (Ops.qword % Uint64.of_int64) ui64 ;
    1, map2 (fun lo hi ->
         oword (Uint128.((shift_left (of_int64 hi) 64) + of_int64 lo))
       ) ui64 ui64 ;
    1, map data_ptr_of_string small_string ;
    1, map alloc_value maybe_nullable_gen ;
  ] in
  let lst =
    if depth > 0 then
      (1,
        pick_from_env l depth (function
          | E0 (Identifier _) -> true
          | _ -> false)) ::
      (1, (
        pick_from_env l depth (function
          | E0 (Param _) -> true
          | _ -> false))) ::
      lst
    else lst in
  frequency lst

(* Pick a param or identifier at random in the environment: *)
and pick_from_env l depth f =
  let open Gen in
  let es =
    List.filter_map (fun (e, _t) -> if f e then Some e else None) l in
  if es <> [] then
    oneofl es
  else
    (* Reroll the dice: *)
    expression_gen (l, depth)

and e1_gen l depth =
  let expr = expression_gen (l, depth - 1) in
  let open Gen in
  frequency [
    1,
      join (
        map (fun ts ->
          let ts = Array.map (fun mn -> TValue mn) ts in
          let fid = get_next_fid () in
          let l =
            Array.fold_lefti (fun l i t ->
              (param fid i, t) :: l
            ) l ts in
          map (fun e ->
            E1 (Function (fid, ts), e)
          ) (expression_gen (l, depth - 1))
        ) (tiny_array maybe_nullable_gen)
      ) ;
    1, map2 comment (string ~gen:printable) expr ;
    1, map2 field_is_null path_gen expr ;
    1, map2 get_field path_gen expr ;
    1, map2 read_word endianness_gen expr ;
    1, map2 read_dword endianness_gen expr ;
    1, map2 read_qword endianness_gen expr ;
    1, map2 read_oword endianness_gen expr ;
    10, map2 (fun n e -> E1 (e1_of_int n, e)) nat expr ]

and e2_gen l depth =
  let expr = expression_gen (l, depth - 1) in
  let open Gen in
  frequency [
    1, map3 let_ let_name_gen expr expr ;
    1, map3 set_field path_gen expr expr ;
    1, map3 peek_word endianness_gen expr expr ;
    1, map3 peek_dword endianness_gen expr expr ;
    1, map3 peek_qword endianness_gen expr expr ;
    1, map3 peek_oword endianness_gen expr expr ;
    1, map3 write_word endianness_gen expr expr ;
    1, map3 write_dword endianness_gen expr expr ;
    1, map3 write_qword endianness_gen expr expr ;
    1, map3 write_oword endianness_gen expr expr ;
    10, map3 (fun n e1 e2 -> E2 (e2_of_int n, e1, e2)) nat expr expr ]

and e3_gen l depth =
  let expr = expression_gen (l, depth - 1) in
  let open Gen in
  map4 (fun n e1 e2 e3 -> E3 (e3_of_int n, e1, e2, e3)) nat expr expr expr

and e4_gen l depth =
  let expr = expression_gen (l, depth - 1) in
  let open Gen in
  map5 (fun n e1 e2 e3 e4 -> E4 (e4_of_int n, e1, e2, e3, e4)) nat expr expr expr expr

and expression_gen (l, depth) =
  let open Gen in
  fix (fun _self (l, depth) ->
    let expr = expression_gen (l, depth - 1) in
    if depth > 0 then
      frequency [
        1, map seq (list_size tiny_int expr) ;
        5, e0_gen l depth ;
        5, e1_gen l depth ;
        5, e2_gen l depth ;
        5, e3_gen l depth ;
        5, e4_gen l depth ]
    else
      e0_gen l depth
  ) (l, depth)

let expression_gen =
  Gen.(sized_size (int_bound 4) (fun n -> expression_gen ([], n)))

let size_of_expression e =
  fold_expr 0 [] (fun n _ _ -> succ n) e

let expression =
  let print = IO.to_string print_expr
  and small = size_of_expression in
  make ~print ~small expression_gen

(*$Q expression & ~count:10_000
  expression (fun e -> \
    let str = IO.to_string E.print_expr e in \
    match E.Parser.expr str with \
    | [ e' ] -> expr_eq e' e \
    | _ -> false)
*)

(*$inject
  open Dessser
  open DessserTools

  let can_be_compiled_with_backend be e =
    let module BE = (val be : BACKEND) in
    let state = BE.make_state () in
    let state, _, _ = BE.identifier_of_expression state e in
    let src_fname =
      let ext = "."^ BE.preferred_def_extension in
      Filename.temp_file "dessserQCheck_" ext in
    let obj_fname = Filename.remove_extension src_fname in
    write_source ~src_fname (BE.print_definitions state) ;
    try compile ~optim:0 ~link:false be src_fname obj_fname ;
        ignore_exceptions Unix.unlink src_fname ;
        ignore_exceptions Unix.unlink obj_fname ;
        true
    with _ -> false

  let can_be_compiled e =
    can_be_compiled_with_backend (module BackEndOCaml : BACKEND) e &&
    can_be_compiled_with_backend (module BackEndCPP : BACKEND) e
*)

(*$Q expression & ~count:10_000
  expression (fun e -> \
    match type_check [] e with \
    | exception _ -> true \
    | () -> can_be_compiled e)
*)