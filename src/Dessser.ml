open Batteries
open Stdint
open DessserTypes
open DessserExpressions
open DessserTools
module T = DessserTypes

(* Used by deserializers to "open" lists: *)
type 'a list_opener =
  (* When a list size is known from the beginning, implement this that
   * returns both the list size and the new src pointer: *)
  | KnownSize of ('a -> maybe_nullable -> path -> maybe_nullable -> (*ptr*) e -> (* (nn * ptr) *) e)
  (* Whereas when the list size is not known beforehand, rather implement
   * this pair of functions, one to parse the ilst header and return the new
   * src pointer and one that will be called before any new token and must
   * return true if the list is finished: *)
  | UnknownSize of
      ('a -> maybe_nullable -> path -> maybe_nullable -> (*ptr*) e -> (*ptr*) e) *
      ('a -> maybe_nullable -> path -> (*ptr*) e -> (*bool*) e)

(* Given the above we can built interesting expressions.
 * A DES(serializer) is a module that implements a particular serialization
 * format in such a way that it provides simple expressions for the basic
 * types that can then be assembled to build either a deserializer from
 * DataPtr to a heap value, or a converter between two formats. *)
module type DES =
sig
  (* No need for a backend (BE) since we merely compute expressions *)
  (* RW state passed to every deserialization operations *)
  type state
  val ptr : maybe_nullable -> typ (* either dataptr or valueptr *)

  val start : maybe_nullable -> (*ptr*) e -> state * (*ptr*) e
  val stop : state -> (*ptr*) e -> (*ptr*) e

  (* A basic value deserializer takes a state, an expression
   * yielding a pointer (either a CodePtr pointing at a byte stream or a
   * ValuePtr pointing at a heap value of type ['b]), and returns two
   * expressions: one yielding the advanced pointer (of the exact same type) and
   * one yielding the value that's been deserialized from the given location: *)
  (* FIXME: make this type "private": *)
  type des = state -> maybe_nullable -> path -> (*ptr*) e -> (* (nn * ptr) *) e

  val dfloat : des
  val dstring : des
  val dbool : des
  val dchar : des
  val di8 : des
  val di16 : des
  val di24 : des
  val di32 : des
  val di40 : des
  val di48 : des
  val di56 : des
  val di64 : des
  val di128 : des
  val du8 : des
  val du16 : des
  val du24 : des
  val du32 : des
  val du40 : des
  val du48 : des
  val du56 : des
  val du64 : des
  val du128 : des

  val tup_opn : state -> maybe_nullable -> path -> maybe_nullable array -> (*ptr*) e -> (*ptr*) e
  val tup_cls : state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val tup_sep : int (* before *) -> state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val rec_opn : state -> maybe_nullable -> path -> (string * maybe_nullable) array -> (*ptr*) e -> (*ptr*) e
  val rec_cls : state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val rec_sep : string (* before *) -> state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val vec_opn : state -> maybe_nullable -> path -> (*dim*) int -> maybe_nullable -> (*ptr*) e -> (*ptr*) e
  val vec_cls : state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val vec_sep : int (* before *) -> state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val list_opn : state list_opener
  val list_cls : state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val list_sep : state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e

  val is_null : state -> maybe_nullable -> path -> (*ptr*) e -> (*bool*) e
  val dnull : value_type -> state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val dnotnull : value_type -> state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
end

(* Same goes for SER(rializers), with the addition that it is also possible to
 * "serialize" into a heap value instead of a data stream:
 * (note: "ssize" stands for "serialized size") *)
type ssize = ConstSize of int | DynSize of (*size*) e

module type SER =
sig
  (* RW state passed to every serialization operations *)
  type state
  val ptr : maybe_nullable -> typ (* either dataptr or valueptr *)

  val start : maybe_nullable -> (*ptr*) e -> state * (*ptr*) e
  val stop : state -> (*ptr*) e -> (*ptr*) e

  (* FIXME: make this type "private": *)
  type ser = state -> maybe_nullable -> path -> (*nn*) e -> (*ptr*) e -> (*ptr*) e

  val sfloat : ser
  val sstring : ser
  val sbool : ser
  val schar : ser
  val si8 : ser
  val si16 : ser
  val si24 : ser
  val si32 : ser
  val si40 : ser
  val si48 : ser
  val si56 : ser
  val si64 : ser
  val si128 : ser
  val su8 : ser
  val su16 : ser
  val su24 : ser
  val su32 : ser
  val su40 : ser
  val su48 : ser
  val su56 : ser
  val su64 : ser
  val su128 : ser

  val tup_opn : state -> maybe_nullable -> path -> maybe_nullable array -> (*ptr*) e -> (*ptr*) e
  val tup_cls : state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val tup_sep : int (* before *) -> state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val rec_opn : state -> maybe_nullable -> path -> (string * maybe_nullable) array -> (*ptr*) e -> (*ptr*) e
  val rec_cls : state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val rec_sep : string (* before *) -> state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val vec_opn : state -> maybe_nullable -> path -> (*dim*) int -> maybe_nullable -> (*ptr*) e -> (*ptr*) e
  val vec_cls : state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val vec_sep : int (* before *) -> state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val list_opn : state -> maybe_nullable -> path -> maybe_nullable -> (*nn*) e option -> (*ptr*) e -> (*ptr*) e
  val list_cls : state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val list_sep : state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e

  val nullable : state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val snull : value_type -> state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e
  val snotnull : value_type -> state -> maybe_nullable -> path -> (*ptr*) e -> (*ptr*) e

  (* Sometimes, we'd like to know in advance how large a serialized value is
   * going to be. Value must have been deserialized into a heap value. *)
  type ssizer = maybe_nullable -> path -> (*value*) e -> ssize
  val ssize_of_float : ssizer
  val ssize_of_string : ssizer
  val ssize_of_bool : ssizer
  val ssize_of_char : ssizer
  val ssize_of_i8 : ssizer
  val ssize_of_i16 : ssizer
  val ssize_of_i24 : ssizer
  val ssize_of_i32 : ssizer
  val ssize_of_i40 : ssizer
  val ssize_of_i48 : ssizer
  val ssize_of_i56 : ssizer
  val ssize_of_i64 : ssizer
  val ssize_of_i128 : ssizer
  val ssize_of_u8 : ssizer
  val ssize_of_u16 : ssizer
  val ssize_of_u24 : ssizer
  val ssize_of_u32 : ssizer
  val ssize_of_u40 : ssizer
  val ssize_of_u48 : ssizer
  val ssize_of_u56 : ssizer
  val ssize_of_u64 : ssizer
  val ssize_of_u128 : ssizer
  (* Specifically for the compound, excluding the size of the parts: *)
  val ssize_of_tup : ssizer
  val ssize_of_rec : ssizer
  val ssize_of_vec : ssizer
  val ssize_of_list : ssizer
  val ssize_of_null : maybe_nullable -> path -> ssize
end

(* Now we can combine a DES and a SER to create a converter from one format
 * into another (including heap values, with some trickery) *)
module DesSer (Des : DES) (Ser : SER) =
struct
  (* Most of the functions below return the src and dst pointers advanced to
   * point to the next value to read/write.
   * [vtyp] denotes the maybe_nullable of the current subfields, whereas
   * [vtyp0] denotes the maybe_nullable of the whole value. *)
  let ds ser des typ sstate dstate vtyp0 path src_dst =
    let what = IO.to_string print_typ typ in
    with_sploded_pair "ds1" src_dst (fun src dst ->
      let v_src = des dstate vtyp0 path src in
      with_sploded_pair "ds2" v_src (fun v src ->
        let open Ops in
        (* dessser handle nulls itself, so that DES/SER implementations
         * do not have to care for nullability. NotNullable is just a cast
         * and has no other effect outside of type_check. *)
        pair
          (comment ("Desserialize a "^ what) src)
          (comment ("Serialize a "^ what) (ser sstate vtyp0 path v dst))))

  let dsfloat = ds Ser.sfloat Des.dfloat float
  let dsstring = ds Ser.sstring Des.dstring string
  let dsbool = ds Ser.sbool Des.dbool bool
  let dschar = ds Ser.schar Des.dchar char
  let dsi8 = ds Ser.si8 Des.di8 i8
  let dsi16 = ds Ser.si16 Des.di16 i16
  let dsi24 = ds Ser.si24 Des.di24 i24
  let dsi32 = ds Ser.si32 Des.di32 i32
  let dsi40 = ds Ser.si40 Des.di40 i40
  let dsi48 = ds Ser.si48 Des.di48 i48
  let dsi56 = ds Ser.si56 Des.di56 i56
  let dsi64 = ds Ser.si64 Des.di64 i64
  let dsi128 = ds Ser.si128 Des.di128 i128
  let dsu8 = ds Ser.su8 Des.du8 u8
  let dsu16 = ds Ser.su16 Des.du16 u16
  let dsu24 = ds Ser.su24 Des.du24 u24
  let dsu32 = ds Ser.su32 Des.du32 u32
  let dsu40 = ds Ser.su40 Des.du40 u40
  let dsu48 = ds Ser.su48 Des.du48 u48
  let dsu56 = ds Ser.su56 Des.du56 u56
  let dsu64 = ds Ser.su64 Des.du64 u64
  let dsu128 = ds Ser.su128 Des.du128 u128

  let dsnull t sstate dstate vtyp0 path src dst =
    let open Ops in
    pair
      (comment "Desserialize NULL" (Des.dnull t dstate vtyp0 path src))
      (comment "Serialize NULL" (Ser.snull t sstate vtyp0 path dst))

  let dsnotnull t sstate dstate vtyp0 path src dst =
    let open Ops in
    pair
      (comment "Desserialize NonNull" (Des.dnotnull t dstate vtyp0 path src))
      (comment "Serialize NonNull" (Ser.snotnull t sstate vtyp0 path dst))

  let rec dstup vtyps sstate dstate vtyp0 path src_dst =
    let open Ops in
    let src_dst = comment "Convert a Tuple"
      (with_sploded_pair "dstup1" src_dst (fun src dst ->
        pair
          (Des.tup_opn dstate vtyp0 path vtyps src)
          (Ser.tup_opn sstate vtyp0 path vtyps dst))) in
    let src_dst =
      BatArray.fold_lefti (fun src_dst i _vtyp ->
        comment ("Convert tuple field "^ Pervasives.string_of_int i)
          (let path = path_append i path in
          if i = 0 then
            desser_ sstate dstate vtyp0 path src_dst
          else
            let src_dst =
              with_sploded_pair "dstup2" src_dst (fun src dst ->
                pair
                  (Des.tup_sep i dstate vtyp0 path src)
                  (Ser.tup_sep i sstate vtyp0 path dst)) in
            desser_ sstate dstate vtyp0 path src_dst)
      ) src_dst vtyps in
    with_sploded_pair "dstup3" src_dst (fun src dst ->
      pair
        (Des.tup_cls dstate vtyp0 path src)
        (Ser.tup_cls sstate vtyp0 path dst))

  and dsrec vtyps sstate dstate vtyp0 path src_dst =
    let open Ops in
    let src_dst =
      with_sploded_pair "dsrec1" src_dst (fun src dst ->
        pair
          (Des.rec_opn dstate vtyp0 path vtyps src)
          (Ser.rec_opn sstate vtyp0 path vtyps dst)) in
    let src_dst =
      BatArray.fold_lefti (fun src_dst i (name, _vtyp) ->
        comment ("Convert record field "^ name)
          (let path = path_append i path in
          if i = 0 then
            desser_ sstate dstate vtyp0 path src_dst
          else
            let src_dst =
              with_sploded_pair "dsrec2" src_dst (fun src dst ->
                pair
                  (Des.rec_sep name dstate vtyp0 path src)
                  (Ser.rec_sep name sstate vtyp0 path dst)) in
            desser_ sstate dstate vtyp0 path src_dst)
      ) src_dst vtyps in
    let src_dst = comment "Convert a Record" src_dst in
    with_sploded_pair "dsrec3" src_dst (fun src dst ->
      pair
        (Des.rec_cls dstate vtyp0 path src)
        (Ser.rec_cls sstate vtyp0 path dst))

  (* This will generates a long linear code with one block per array
   * item, which should be ok since vector dimension is expected to be small.
   * TODO: use one of the loop expressions instead if the dimension is large *)
  and dsvec dim vtyp sstate dstate vtyp0 path src_dst =
    let open Ops in
    let src_dst =
      with_sploded_pair "dsvec1" src_dst (fun src dst ->
        pair
          (Des.vec_opn dstate vtyp0 path dim vtyp src)
          (Ser.vec_opn sstate vtyp0 path dim vtyp dst)) in
    let rec loop src_dst i =
      (* Not really required to keep the actual index, as all indices share the
       * same type, but helps with debugging: *)
      let path = path_append i path in
      if i >= dim then
        with_sploded_pair "dsvec2" src_dst (fun src dst ->
          pair
            (Des.vec_cls dstate vtyp0 path src)
            (Ser.vec_cls sstate vtyp0 path dst))
      else (
        let src_dst =
          if i = 0 then
            src_dst
          else
            with_sploded_pair "dsvec3" src_dst (fun src dst ->
              pair
                (Des.vec_sep i dstate vtyp0 path src)
                (Ser.vec_sep i sstate vtyp0 path dst)) in
        (* FIXME: comment is poorly located: *)
        let src_dst =
          comment ("Convert field #"^ Pervasives.string_of_int i)
            (desser_ sstate dstate vtyp0 path src_dst) in
        loop src_dst (i + 1)
      )
    in
    let what =
      Printf.sprintf2 "Convert a vector of %d %a"
        dim print_maybe_nullable vtyp in
    comment what (loop src_dst 0)

  and dslist vtyp sstate dstate vtyp0 path src_dst =
    let open Ops in
    let pair_ptrs = TPair (Des.ptr vtyp0, Ser.ptr vtyp0) in
    (* Pretend we visit only the index 0, which is enough to determine
     * subtypes: *)
    let path = path_append 0 path in
    comment "Convert a List"
      (with_sploded_pair "dslist1" src_dst (fun src dst ->
        (* FIXME: for some deserializers (such as SExpr) it's not easy to
         * know the list length in advance. For those, it would be better
         * to call a distinct 'end-of-list' function returning a bool and
         * read until this returns true. We could simply have both, and
         * here we would repeat_while ~cond:(n<count && not end_of_list),
         * then SEpxr would merely return a very large number of entries
         * (better than to return a single condition in list_opn for non
         * functional backends such as, eventually, C?) *)
        let src_dst =
          match Des.list_opn with
          | KnownSize list_opn ->
              let dim_src = list_opn dstate vtyp0 path vtyp src in
              with_sploded_pair "dslist2" dim_src (fun dim src ->
                let dst = Ser.list_opn sstate vtyp0 path vtyp (Some dim) dst in
                repeat ~from:(i32 0l) ~to_:(to_i32 dim)
                  ~body:(comment "Convert a list item"
                    (func2 T.i32 pair_ptrs (fun n src_dst ->
                      let src_dst =
                        choose
                          ~cond:(eq n (i32 0l))
                          src_dst
                          (with_sploded_pair "dslist3" src_dst (fun psrc pdst ->
                            pair
                              (Des.list_sep dstate vtyp0 path psrc)
                              (Ser.list_sep sstate vtyp0 path pdst))) in
                      desser_ sstate dstate vtyp0 path src_dst)))
                  ~init:(pair src dst))
          | UnknownSize (list_opn, end_of_list) ->
              let t_fst_src_dst = TPair (T.bool, pair_ptrs) in
              let src = list_opn dstate vtyp0 path vtyp src in
              let dst = Ser.list_opn sstate vtyp0 path vtyp None dst in
              let fst_src_dst =
                loop_while
                  ~cond:(comment "Test end of list"
                    (func1 t_fst_src_dst (fun fst_src_dst ->
                      let src_dst = snd fst_src_dst in
                      not_ (end_of_list dstate vtyp0 path (fst src_dst)))))
                  ~body:(comment "Convert a list item"
                    (func1 t_fst_src_dst (fun fst_src_dst ->
                      with_sploded_pair "dslist4" fst_src_dst (fun is_fst src_dst ->
                        let src_dst =
                          choose
                            ~cond:is_fst
                            src_dst
                            (with_sploded_pair "dslist5" src_dst (fun psrc pdst ->
                              pair
                                (Des.list_sep dstate vtyp0 path psrc)
                                (Ser.list_sep sstate vtyp0 path pdst))) in
                        pair
                          (bool false)
                          (desser_ sstate dstate vtyp0 path src_dst)))))
                  ~init:(pair (bool true) (pair src dst)) in
              snd fst_src_dst
        in
        with_sploded_pair "dslist6" src_dst (fun src dst ->
          pair
            (Des.list_cls dstate vtyp0 path src)
            (Ser.list_cls sstate vtyp0 path dst))))

  and desser_value_type = function
    | Mac TFloat -> dsfloat
    | Mac TString -> dsstring
    | Mac TBool -> dsbool
    | Mac TChar -> dschar
    | Mac TI8 -> dsi8
    | Mac TI16 -> dsi16
    | Mac TI24 -> dsi24
    | Mac TI32 -> dsi32
    | Mac TI40 -> dsi40
    | Mac TI48 -> dsi48
    | Mac TI56 -> dsi56
    | Mac TI64 -> dsi64
    | Mac TI128 -> dsi128
    | Mac TU8 -> dsu8
    | Mac TU16 -> dsu16
    | Mac TU24 -> dsu24
    | Mac TU32 -> dsu32
    | Mac TU40 -> dsu40
    | Mac TU48 -> dsu48
    | Mac TU56 -> dsu56
    | Mac TU64 -> dsu64
    | Mac TU128 -> dsu128
    | Usr t -> desser_value_type t.def
    | TTup vtyps -> dstup vtyps
    | TRec vtyps -> dsrec vtyps
    | TVec (dim, vtyp) -> dsvec dim vtyp
    | TList vtyp -> dslist vtyp
    | TMap _ -> assert false (* No value of map type *)

  and desser_ sstate dstate vtyp0 path src_dst =
    let open Ops in
    let vtyp = type_of_path vtyp0 path in
    match vtyp with
    | Nullable t ->
        with_sploded_pair "desser_" src_dst (fun src dst ->
          let cond = Des.is_null dstate vtyp0 path src in
          (* Des can use [is_null] to prepare for a nullable, but Ser might also
           * have some work to do: *)
          let dst = Ser.nullable sstate vtyp0 path dst in
          (* XXX WARNING XXX
           * if any of dnull/snull/snotnull/etc update the state, they will
           * do so in both branches of this alternative. *)
          choose ~cond
            (dsnull t sstate dstate vtyp0 path src dst)
            (dsnotnull t sstate dstate vtyp0 path src dst |>
             desser_value_type t sstate dstate vtyp0 path))
    | NotNullable t ->
        desser_value_type t sstate dstate vtyp0 path src_dst

  let desser vtyp0 src dst =
    let open Ops in
    let sstate, dst = Ser.start vtyp0 dst
    and dstate, src = Des.start vtyp0 src in
    let src_dst = pair src dst in
    let src_dst = desser_ sstate dstate vtyp0 [] src_dst in
    with_sploded_pair "desser" src_dst (fun src dst ->
      pair
        (Des.stop dstate src)
        (Ser.stop sstate dst))
end

(*
 * Now let's move on to code generators.
 *
 * The idea is that a code generator receives its state, an expression and an
 * optional name for it, and returns an identifier alongside a new state.
 *
 * This state has all defined identifiers.
 *
 * Eventually, the state can be turned into a source file. Unused identifiers
 * may not be included unless they are non-anonymous functions.
 *)

module type BACKEND =
sig
  type state
  val make_state : unit -> state
  val print_definitions : state -> unit IO.output -> unit
  val print_declarations : state -> unit IO.output -> unit
  val print_comment : unit IO.output -> ('a, unit IO.output, unit) format -> 'a

  (* Returns the new state, the Identifier expression to use in new expressions,
   * and the identifier name in the source code.
   * Expression is not allowed to have the null type (which would make little
   * sense anyway): *)
  val identifier_of_expression : state -> ?name:string -> e -> (state * e * string)
  val preferred_def_extension : string
  val preferred_decl_extension : string
  val compile_cmd : optim:int -> link:bool -> string -> string -> string
end
