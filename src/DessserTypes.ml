open Batteries
open Stdint

module PConfig = ParsersPositions.LineCol (Parsers.SimpleConfig (Char))
module P = Parsers.Make (PConfig)

let pp = Printf.fprintf

(* Basic scalar types that can be used to define more specialized user types *)

type mac_type =
  | TFloat | TString | TBool | TChar
  | TU8 | TU16 | TU24 | TU32 | TU40 | TU48 | TU56 | TU64 | TU128
  | TI8 | TI16 | TI24 | TI32 | TI40 | TI48 | TI56 | TI64 | TI128

(* Machine-types are the basic types from which more specialized types can be
 * build. Those constructed types are called user-types.
 * User types specialize machine types in several ways: they have their own
 * name, pretty-printer, parser, and of course an implementation as the
 * corresponding machine type.
 * Notice that user types cannot be parameterized (yet). So only scalar user
 * types are possible for now.
 * User expressions can restrict types to user types. *)

and user_type =
  { name : string ;
    print : 'a. 'a IO.output -> unit ;
    mutable parse : value_type P.t ;
    def : value_type }

(* Those types describing values that can be (de)serialized.
 * All of them can possibly be nullable.
 * User types are build from those value types. *)

and value_type =
  | Mac of mac_type
  | Usr of user_type
  (* Compound types: *)
  | TVec of int * maybe_nullable
  | TList of maybe_nullable
  | TTup of maybe_nullable array
  (* Exact same as a tuple, but with field names that can be used as
   * accessors (also used to name actual fields in generated code): *)
  | TRec of (string * maybe_nullable) array
  (* The type for maps exist because there will be some operations using
   * that type indirectly (such as fetching from a DB by key, or describing
   * a key->value mapping in a type expression). But there is no value of
   * that type, ever. From a (de)serialized point of view, maps are
   * equivalent to association lists. *)
  | TMap of maybe_nullable * maybe_nullable
  (* TODO: sum types *)

and maybe_nullable =
  | Nullable of value_type
  | NotNullable of value_type

let rec value_type_eq vt1 vt2 =
  match vt1, vt2 with
  | Mac mt1, Mac mt2 ->
      mt1 = mt2
  | Usr ut1, Usr ut2 ->
      ut1.name = ut2.name
  | TVec (d1, mn1), TVec (d2, mn2) ->
      d1 = d2 && maybe_nullable_eq mn1 mn2
  | TList mn1, TList mn2 ->
      maybe_nullable_eq mn1 mn2
  | TTup mn1s, TTup mn2s ->
      Array.length mn1s = Array.length mn2s &&
      Array.for_all2 maybe_nullable_eq mn1s mn2s
  | TRec mn1s, TRec mn2s ->
      Array.length mn1s = Array.length mn2s &&
      Array.for_all2 (fun (n1, mn1) (n2, mn2) ->
        n1 = n2 && maybe_nullable_eq mn1 mn2
      ) mn1s mn2s
  | TMap (k1, v1), TMap (k2, v2) ->
      maybe_nullable_eq k1 k2 && maybe_nullable_eq v1 v2
  | _ ->
      false

and maybe_nullable_eq mn1 mn2 =
  match mn1, mn2 with
  | Nullable vt1, Nullable vt2 -> value_type_eq vt1 vt2
  | NotNullable vt1, NotNullable vt2 -> value_type_eq vt1 vt2
  | _ -> false

let is_nullable = function
  | Nullable _ -> true
  | NotNullable _ -> false

let to_value_type = function
  | Nullable t -> t
  | NotNullable t -> t

let to_nullable = function
  | NotNullable t -> Nullable t
  | Nullable _ as x -> x

let print_mac_type oc =
  let sp = String.print oc in
  function
  | TFloat -> sp "Float"
  | TString -> sp "String"
  | TBool -> sp "Bool"
  | TChar -> sp "Char"
  | TU8 -> sp "U8"
  | TU16 -> sp "U16"
  | TU24 -> sp "U24"
  | TU32 -> sp "U32"
  | TU40 -> sp "U40"
  | TU48 -> sp "U48"
  | TU56 -> sp "U56"
  | TU64 -> sp "U64"
  | TU128 -> sp "U128"
  | TI8 -> sp "I8"
  | TI16 -> sp "I16"
  | TI24 -> sp "I24"
  | TI32 -> sp "I32"
  | TI40 -> sp "I40"
  | TI48 -> sp "I48"
  | TI56 -> sp "I56"
  | TI64 -> sp "I64"
  | TI128 -> sp "I128"

let rec print_value_type oc = function
  | Mac t ->
      print_mac_type oc t
  | Usr t ->
      t.print oc
  | TVec (dim, vt) ->
      pp oc "%a[%d]" print_maybe_nullable vt dim
  | TList vt ->
      pp oc "%a[]" print_maybe_nullable vt
  | TTup vts ->
      pp oc "%a"
        (Array.print ~first:"(" ~last:")" ~sep:";" print_maybe_nullable) vts
  | TRec vts ->
      pp oc "%a"
        (Array.print ~first:"{" ~last:"}" ~sep:";"
          (fun oc (n, t) ->
            pp oc "%s: %a" n print_maybe_nullable t)
        ) vts
  | TMap (k, v) ->
      pp oc "%a[%a]"
        print_maybe_nullable v
        print_maybe_nullable k

and print_maybe_nullable oc = function
  | Nullable t ->
      pp oc "%a?" print_value_type t
  | NotNullable t ->
      print_value_type oc t

let user_types = Hashtbl.create 50

(* To all the above types we add a few low-level types that can not be used
 * in values but are useful to manipulate them. *)
type typ =
  | TValue of maybe_nullable
  | TVoid
  (* DataPtr are used to point into the stream of bytes that's being
   * serialized into / deserialized from. The type of the value that's
   * being (de)serialized is kept nonetheless. *)
  | TDataPtr
  (* ValuePtr are used to point at heap allocated values of a given type.
   * The "offset" is then the location in that data structure, and it is
   * "advanced" by hopping from subfield to subfields, traversing the
   * structure depth first. The path is thus merely an integer, but the
   * backend has to know how to locate each addressable leaves. *)
  | TValuePtr of maybe_nullable
  (* A size in byte. *)
  | TSize
  (* Data access, may be just pointer to the actual serialized object: *)
  | TBit
  | TByte
  | TWord
  | TDWord
  | TQWord
  | TOWord
  | TBytes
  | TPair of typ * typ
  | TFunction of typ array * (* result: *) typ

let rec typ_eq t1 t2 =
  match t1, t2 with
  | TValue mn1, TValue mn2
  | TValuePtr mn1, TValuePtr mn2 ->
      maybe_nullable_eq mn1 mn2
  | TPair (t11, t12), TPair (t21, t22) ->
      typ_eq t11 t21 && typ_eq t12 t22
  | TFunction (pt1, rt1), TFunction (pt2, rt2) ->
      Array.for_all2 typ_eq pt1 pt2 && typ_eq rt1 rt2
  | t1, t2 -> t1 = t2

let rec print_typ oc =
  let sp = String.print oc in
  function
  | TValue vt ->
      print_maybe_nullable oc vt
  | TVoid -> sp "Void"
  | TDataPtr -> sp "DataPtr"
  | TValuePtr t ->
      pp oc "(%a ValuePtr)" print_maybe_nullable t
  | TSize -> sp "Size"
  | TBit -> sp "Bit"
  | TByte -> sp "Byte"
  | TWord -> sp "Word"
  | TDWord -> sp "DWord"
  | TQWord -> sp "QWord"
  | TOWord -> sp "OWord"
  | TBytes -> sp "Bytes"
  | TPair (t1, t2) ->
      pp oc "(%a * %a)"
        print_typ t1
        print_typ t2
  | TFunction ([||], t1) ->
      pp oc "( -> %a)" print_typ t1
  | TFunction (ts, t2) ->
      pp oc "(%a -> %a)"
        (Array.print ~first:"" ~last:"" ~sep:"->" print_typ) ts
        print_typ t2

let typ_to_nullable = function
  | TValue (NotNullable t) -> TValue (Nullable t)
  | t ->
      Printf.eprintf "Cannot turn type %a into nullable\n%!"
        print_typ t ;
      assert false

let typ_to_not_nullable = function
  | TValue (Nullable t) -> TValue (NotNullable t)
  | t ->
      Printf.eprintf "Cannot turn type %a into not-nullable\n%!"
        print_typ t ;
      assert false

module Parser =
struct
  module ParseUsual = ParsersUsual.Make (P)
  include P
  include ParseUsual

  let comment =
    ref (
      let all_but_newline =
        cond "anything until newline" (fun c -> c <> '\n' && c <> '\r') '_'
      in
      fun m ->
        let m = "comment" :: m in
        (
          char '-' -- char '-' --
          repeat_greedy ~sep:none ~what:"comment" all_but_newline
        ) m
    )

  let blanks =
    ref (
      let blank = ParseUsual.blank >>: ignore
      and newline = ParseUsual.newline >>: ignore in
      fun m ->
        let m = "blanks" :: m in
        (
        repeat_greedy ~min:1 ~sep:none ~what:"whitespaces"
          (blank ||| newline ||| !comment) >>: ignore
        ) m
    )

  let opt_blanks =
    optional_greedy ~def:() !blanks

  let allow_surrounding_blanks p =
    opt_blanks -+ p +- opt_blanks +- eof

  let opt_question_mark =
    optional ~def:false (char '?' >>: fun _ -> true)

  let pos_integer what m =
    let m = what :: m in
    (
      decimal_number >>: fun n ->
        let i = Num.to_int n in
        if i < 0 then raise (Reject "must be positive")
        else i
    ) m

  (* strinG will match the given string regardless of the case and
   * regardless of the surrounding (ie even if followed by other letters). *)
  let strinG s =
    dismiss_error_if (parsed_fewer_than (String.length s / 2))
      (ParseUsual.string ~case_sensitive:false s)

  let make_type nullable vtyp =
    if nullable then Nullable vtyp else NotNullable vtyp

  let tup_sep =
    opt_blanks -- char ';' -- opt_blanks

  let user_type = ref fail

  type key_type = VecDim of int | ListDim | MapKey of maybe_nullable

  let rec reduce_dims t = function
    | [] -> t
    | (VecDim d, nullable) :: rest ->
        reduce_dims (make_type nullable (TVec (d, t))) rest
    | (ListDim, nullable) :: rest ->
        reduce_dims (make_type nullable (TList t)) rest
    | (MapKey k, nullable) :: rest ->
        reduce_dims (make_type nullable (TMap (k, t))) rest

  let rec key_type m =
    let vec_dim m =
      let m = "vector dimension" :: m in
      (
        char '[' -- opt_blanks -+
        pos_integer "vector dimensions" +-
        opt_blanks +- char ']' ++
        opt_question_mark >>: fun (d, n) ->
          if d <= 0 then
            raise (Reject "Vector must have strictly positive dimension") ;
          VecDim d, n
      ) m
    and list_dim m =
      let m = "list type" :: m in
      (
         char '[' -- opt_blanks -- char ']' -+
        opt_question_mark >>: fun n ->
          ListDim, n
      ) m
    and map_key m =
      let m = "map key" :: m in
      (
        char '[' -- opt_blanks -+
          maybe_nullable +- opt_blanks +- char ']' ++
        opt_question_mark >>: fun (k, n) ->
          MapKey k, n
      ) m
    in
    (
      vec_dim ||| list_dim ||| map_key
    ) m

  and maybe_nullable m =
    let m = "type" :: m in
    (
      (
        scalar_typ ||| tuple_typ ||| record_typ |||
        (!user_type ++ opt_question_mark >>: fun (vt, n) -> make_type n vt)
      ) ++
      repeat ~sep:opt_blanks (key_type) >>: fun (t, dims) ->
        reduce_dims t dims
    ) m

  and scalar_typ m =
    let m = "scalar type" :: m in
    let st n mtyp =
      let vtyp = Mac mtyp in
      (strinG (n ^"?") >>: fun () -> make_type true vtyp) |||
      (strinG n >>: fun () -> make_type false vtyp)
    in
    (
      (st "float" TFloat) |||
      (st "string" TString) |||
      (st "bool" TBool) |||
      (st "boolean" TBool) |||
      (st "char" TChar) |||
      (st "u8" TU8) |||
      (st "u16" TU16) |||
      (st "u24" TU24) |||
      (st "u32" TU32) |||
      (st "u40" TU40) |||
      (st "u48" TU48) |||
      (st "u56" TU56) |||
      (st "u64" TU64) |||
      (st "u128" TU128) |||
      (st "i8" TI8) |||
      (st "i16" TI16) |||
      (st "i24" TI24) |||
      (st "i32" TI32) |||
      (st "i40" TI40) |||
      (st "i48" TI48) |||
      (st "i56" TI56) |||
      (st "i64" TI64) |||
      (st "i128" TI128)
    ) m

  and tuple_typ m =
    let m = "tuple type" :: m in
    (
      char '(' -- opt_blanks -+
        several ~sep:tup_sep maybe_nullable
      +- opt_blanks +- char ')' ++
      opt_question_mark >>: fun (ts, nullable) ->
        make_type nullable (TTup (Array.of_list ts))
    ) m

  and record_typ m =
    let m = "record type" :: m in
    let field_typ =
      identifier +- opt_blanks +- char ':' +- opt_blanks ++ maybe_nullable in
    (
      char '{' -- opt_blanks -+
        several ~sep:tup_sep field_typ +-
      opt_blanks +- char '}' ++
      opt_question_mark >>: fun (ts, nullable) ->
        make_type nullable (TRec (Array.of_list ts))
    ) m

  let string_parser ?what ~print p =
    let what =
      match what with None -> [] | Some w -> [w] in
    let p = allow_surrounding_blanks p in
    fun s ->
      let stream = stream_of_string s in
      let parse_with_err_budget e =
        let c = ParsersBoundedSet.make e in
        p what None c stream |> to_result in
      let err_out e =
        Printf.sprintf2 "Parse error: %a"
          (print_bad_result print) e |>
        failwith
      in
      let try_fix_typos = true in
      match parse_with_err_budget 0 with
      | Bad e ->
          if try_fix_typos then
            (* Try again with some error correction activated, in order to
             * get a better error message: *)
            match parse_with_err_budget 1 with
            | Bad e -> err_out e
            | _ -> assert false
          else
            err_out e
      | Ok (res, _) ->
          res

  let maybe_nullable_of_string ?what =
    let print = print_maybe_nullable in
    string_parser ~print ?what maybe_nullable

  (*$< Parser *)
  (*$inject
    open Batteries

    let test_printer res_printer = function
      | Ok (res, (_, [])) ->
        Printf.sprintf "%s" (IO.to_string res_printer res)
      | Ok (res, (len, rest)) ->
        Printf.sprintf "%S, parsed_len=%d, rest=%s"
          (IO.to_string res_printer res) len
          (IO.to_string (List.print Char.print) rest)
      | Bad (Approximation _) ->
        "Approximation"
      | Bad (NoSolution e) ->
        Printf.sprintf "No solution (%s)" (IO.to_string print_error e)
      | Bad (Ambiguous lst) ->
        Printf.sprintf "%d solutions: %s"
          (List.length lst)
          (IO.to_string
            (List.print (fun oc (res, _corr, (_stream, pos)) ->
              Printf.fprintf oc "res=%a, pos=%d,%d"
                res_printer res
                pos.ParsersPositions.line pos.column)) lst)

    let strip_linecol = function
      | Ok (res, (x, _pos)) -> Ok (res, x)
      | Bad x -> Bad x

    let test_p ?(postproc=identity) p s =
      (p +- eof) [] None Parsers.no_error_correction (PConfig.stream_of_string s) |>
      to_result |>
      strip_linecol |>
      Result.map (fun (r, rest) -> postproc r, rest)

    open DessserTypes
  *)

  (*$= maybe_nullable & ~printer:(test_printer print_maybe_nullable)
    (Ok ((NotNullable (Mac TU8)), (2,[]))) \
       (test_p maybe_nullable "u8")
    (Ok ((Nullable (Mac TU8)), (3,[]))) \
       (test_p maybe_nullable "u8?")
    (Ok ((NotNullable (TVec (3, (NotNullable (Mac TU8))))), (5,[]))) \
       (test_p maybe_nullable "u8[3]")
    (Ok ((NotNullable (TVec (3, (Nullable (Mac TU8))))), (6,[]))) \
       (test_p maybe_nullable "u8?[3]")
    (Ok ((Nullable (TVec (3, (NotNullable (Mac TU8))))), (6,[]))) \
       (test_p maybe_nullable "u8[3]?")
    (Ok ((NotNullable (TVec (3, (Nullable (TList (NotNullable (Mac TU8))))))), (8,[]))) \
       (test_p maybe_nullable "u8[]?[3]")
    (Ok ((Nullable (TList (NotNullable (TVec (3, (Nullable (Mac TU8))))))), (9,[]))) \
       (test_p maybe_nullable "u8?[3][]?")
    (Ok ((Nullable (TMap ((NotNullable (Mac TString)), (NotNullable (Mac TU8))))), (11,[]))) \
       (test_p maybe_nullable "u8[string]?")
    (Ok ((NotNullable (TMap ((NotNullable (TMap ((Nullable (Mac TU8)), (Nullable (Mac TString))))), (Nullable (TList ((NotNullable (TTup [| (NotNullable (Mac TU8)) ; (NotNullable (TMap ((NotNullable (Mac TString)), (NotNullable (Mac TBool))))) |])))))))), (35,[]))) \
       (test_p maybe_nullable "(u8; bool[string])[]?[string?[u8?]]")
    (Ok ((NotNullable (TRec [| "f1", NotNullable (Mac TBool) ; "f2", Nullable (Mac TU8) |])), (19,[]))) \
      (test_p maybe_nullable "{f1: Bool; f2: U8?}")
    (Ok ((NotNullable (TVec (1, NotNullable (Mac TBool)))), (7,[]))) \
      (test_p maybe_nullable "Bool[1]")
  *)

  let rec typ m =
    let m = "typ" :: m in
    (
      (maybe_nullable >>: fun mn -> TValue mn) |||
      (strinG "void" >>: fun () -> TVoid) |||
      (strinG "dataptr" >>: fun () -> TDataPtr) |||
      (
        char '(' -- opt_blanks -+
          maybe_nullable +- !blanks +- strinG "valueptr" +-
        opt_blanks +- char ')' >>:
          fun mn -> TValuePtr mn
      ) |||
      (strinG "size" >>: fun () -> TSize) |||
      (strinG "bit" >>: fun () -> TBit) |||
      (strinG "byte" >>: fun () -> TByte) |||
      (strinG "word" >>: fun () -> TWord) |||
      (strinG "dword" >>: fun () -> TDWord) |||
      (strinG "qword" >>: fun () -> TQWord) |||
      (strinG "oword" >>: fun () -> TOWord) |||
      (strinG "bytes" >>: fun () -> TBytes) |||
      (
        char '(' -- opt_blanks -+ typ +- opt_blanks +-
        char '*' +- opt_blanks ++ typ +- opt_blanks +- char ')' >>:
          fun (t1, t2) -> TPair (t1, t2)
      ) |||
      (
        let sep = opt_blanks -- char '-' -- char '>' -- opt_blanks in
        char '(' -+
          repeat ~sep typ +- sep ++ typ +- opt_blanks +-
        char ')' >>: fun (ptyps, rtyp) ->
          TFunction (Array.of_list ptyps, rtyp)
      )
    ) m

  let typ_of_string ?what =
    let print = print_typ in
    string_parser ~print ?what typ

  (*$>*)
end

type gen_printer = { f : 'a. 'a IO.output -> unit }

let register_user_type
    name ?(print : gen_printer option) ?(parse : value_type P.t option) def =
  Hashtbl.modify_opt name (function
    | None ->
        let print = match print with
          | Some printer ->
              printer.f
          | None -> fun oc ->
              String.print oc name in
        let ut = { name ; print ; parse = P.fail ; def } in
        let parse = match parse with
          | Some p -> p
          | None -> Parser.(strinG name >>: fun () -> Usr ut) in
        ut.parse <- parse ;
        Parser.user_type := Parser.(oneof !user_type parse) ;
        Some ut
    | Some _ ->
        invalid_arg "register_user_type"
  ) user_types

let get_user_type = Hashtbl.find user_types

(* Examples: *)
let () =
  register_user_type "Date" (Mac TFloat) ;
  register_user_type "Eth" (Mac TU48) ;
  register_user_type "Ipv4" (Mac TU32) ;
  register_user_type "Ipv6" (Mac TU128) ;
  register_user_type "Cidrv4" (TTup [| NotNullable (Usr (get_user_type "Ipv4")) ;
                                       NotNullable (Mac TU8) |]) ;
  register_user_type "Cidrv6" (TTup [| NotNullable (Usr (get_user_type "Ipv6")) ;
                                       NotNullable (Mac TU8) |])

(* Paths are used to locate subfields within compound types.
 * Head of the list is the index of the considered type child, then
 * the index of the grandchild, and so on. *)
(* FIXME: a data structure that can be appended/prepended/matched from both ends *)
type path = int list

let print_path oc p =
  List.print ~first:"" ~last:"" ~sep:"/" Int.print oc p

let path_of_string s =
  String.split_on_char '/' s |>
  List.map int_of_string

let rec type_of_path t path =
  match path with
  | [] -> t
  | i :: path ->
      let rec type_of_not_nullable = function
        | NotNullable (Mac _ | TMap _) ->
            assert false
        | NotNullable (Usr t) ->
            type_of_not_nullable (NotNullable t.def)
        | NotNullable (TVec (dim, vt)) ->
            assert (i < dim) ;
            type_of_path vt path
        | NotNullable (TList vt) ->
            type_of_path vt path
        | NotNullable (TTup vts) ->
            assert (i < Array.length vts) ;
            type_of_path vts.(i) path
        | NotNullable (TRec vts) ->
            assert (i < Array.length vts) ;
            type_of_path (snd vts.(i)) path
        | Nullable x ->
            type_of_not_nullable (NotNullable x) in
      type_of_not_nullable t

(*$inject
  let test_t = NotNullable (TTup [|
    NotNullable (Mac TU8) ;
    Nullable (Mac TString) ;
    Nullable (TVec (2, NotNullable (Mac TChar))) |])
*)

(*$= type_of_path & ~printer:(BatIO.to_string print_maybe_nullable)
  test_t (type_of_path test_t [])
  (NotNullable (Mac TU8)) (type_of_path test_t [0])
  (Nullable (Mac TString)) (type_of_path test_t [1])
  (Nullable (TVec (2, NotNullable (Mac TChar)))) (type_of_path test_t [2])
  (NotNullable (Mac TChar)) (type_of_path test_t [2; 0])
*)

(* Some short cuts for often used types: *)

let bool = TValue (NotNullable (Mac TBool))
let char = TValue (NotNullable (Mac TChar))
let nstring = TValue (Nullable (Mac TString))
let string = TValue (NotNullable (Mac TString))
let float = TValue (NotNullable (Mac TFloat))
let u8 = TValue (NotNullable (Mac TU8))
let u16 = TValue (NotNullable (Mac TU16))
let u24 = TValue (NotNullable (Mac TU24))
let u32 = TValue (NotNullable (Mac TU32))
let u40 = TValue (NotNullable (Mac TU40))
let u48 = TValue (NotNullable (Mac TU48))
let u56 = TValue (NotNullable (Mac TU56))
let u64 = TValue (NotNullable (Mac TU64))
let u128 = TValue (NotNullable (Mac TU128))
let i8 = TValue (NotNullable (Mac TI8))
let i16 = TValue (NotNullable (Mac TI16))
let i24 = TValue (NotNullable (Mac TI24))
let i32 = TValue (NotNullable (Mac TI32))
let i40 = TValue (NotNullable (Mac TI40))
let i48 = TValue (NotNullable (Mac TI48))
let i56 = TValue (NotNullable (Mac TI56))
let i64 = TValue (NotNullable (Mac TI64))
let i128 = TValue (NotNullable (Mac TI128))
let void = TVoid
let bit = TBit
let byte = TByte
let size = TSize
let word = TWord
let dword = TDWord
let qword = TQWord
let oword = TOWord
let bytes = TBytes
let dataptr = TDataPtr
let valueptr t = TValuePtr t
let pair t1 t2 = TPair (t1, t2)