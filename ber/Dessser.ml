(* BerSerde is a library that generates serializers and deserializers
 * between a choice of several external formats and several internal
 * representations. *)
(* Objectives:
 * 1. Be able to add serialization format easily
 * 2. Do not rely too much on large code values with OCaml code but rather
 *    try to combine smaller ones so that it's possible to lift them in C
 *    expressions instead of printing OCaml.
 * 3. Integrate nicely with Ramen types and type checker (ie: no need to ask
 *    to much to OCaml's typechecker since we are going to typecheck with z3)
 *)
open Batteries
open Stdint

(* Serialized data are read from / written to memory buffers accessed via this
 * interface.
 * You will find several implementations:
 * - One reading/writing into a Bytes.t;
 * - One reading/writing into a file;
 * - Other should be easy to add. *)
module type SERDATA =
sig
  (* Add a way to save past locations in a stack, to mask location of nullmasks
   * for instance *)
  type pointer
  type size
  val add : pointer code -> size code -> pointer code
  val sub : pointer code -> pointer code -> size code
  val rem : pointer code -> size code
  val print_pointer : ('a IO.output -> pointer -> unit) code
  val print_data : ('a IO.output -> pointer -> size -> unit) code

  type bit
  type byte
  type word
  type dword
  type qword
  type oword
  type bytes

  val int_of_byte : byte code -> int code
  val byte_of_int : int code -> byte code

  val test_bit : pointer code -> int code -> bit code
  (* read functions: *)
  val read_byte : pointer code -> (byte * pointer) code
  val read_word : ?be:bool -> pointer code -> (word * pointer) code
  val read_dword : ?be:bool -> pointer code -> (dword * pointer) code
  val read_qword : ?be:bool -> pointer code -> (qword * pointer) code
  val read_oword : ?be:bool -> pointer code -> (oword * pointer) code
  (* signature suitable for application: *)
  val read_bytes : (size * pointer) code -> (bytes * pointer) code
  val set_bit : pointer code -> int code -> bit code -> unit code
  (* write functions: *)
  val write_byte : pointer code -> byte code -> pointer code
  val write_word : ?be:bool -> pointer code -> word code -> pointer code
  val write_dword : ?be:bool -> pointer code -> dword code -> pointer code
  val write_qword : ?be:bool -> pointer code -> qword code -> pointer code
  val write_oword : ?be:bool -> pointer code -> oword code -> pointer code
  val write_bytes : pointer code -> bytes code -> pointer code
  (* Those two do not move the pointer: *)
  val peek_byte : ?at:size -> pointer code -> byte code
  val peek_word : ?be:bool -> ?at:size -> pointer code -> word code
  val peek_dword : ?be:bool -> ?at:size -> pointer code -> dword code
  val peek_qword : ?be:bool -> ?at:size -> pointer code -> qword code
  val peek_oword : ?be:bool -> ?at:size -> pointer code -> oword code
  val poke_byte : pointer code -> byte code -> unit code

  (* Those should return the values rather than code values but that allows
   * to work around many instances of the unquoted Obj.majic issue: *)
  val byte_of_const : int -> byte
  val word_of_const : int -> word
  val dword_of_const : Uint32.t -> dword
  val qword_of_const : Uint64.t -> qword
  val oword_of_const : Uint128.t -> oword
  val size_of_const : int -> size
  val make_buffer : size code -> pointer code
  val of_string : string code -> pointer code
  val bytes_append : bytes code -> byte code -> bytes code
  val make_bytes : bytes code
end

(* Now when we generate code expressions we want to generate ocaml code (or
 * C code) without carrying along the types nor the value type tags. The
 * generator must either generate working code of fail in an assert false
 * (we do not rely on the type checker to avoid the asserts but on z3). *)

(* For instance, if we know that the 3rd item of a tuple is a i8 value,
 * then the generated code to write this 3rd item must be: `write x_3` not
 *   `write (match x_3 with VI8 v -> v)`.
 * How to do that?
 * if v is the value for the tuple, then we can do:
 *   (i8v_of_value v.(3))
 * to get the i8v (int code).
 * So the only thing that's missing to implement tuple_get et vec_get is the
 * vector and tuple *types*, that could be part of the value.
 *
 * Now what if the item we want is only known at runtime. For vectors that
 * must not be a problem as the type is still known at compile time. For
 * a tuple this is just not possible.
 *)

module Type =
struct
  type t = { nullable : bool ; structure : structure }
  and structure =
    | TFloat
    | TString
    | TBool
    | TU8 | TU16 | TU32 | TU64 | TU128
    | TI8 | TI16 | TI32 | TI64 | TI128
    | TVec of int * t
    | TTup of t array

  let make ?(nullable=false) structure = { nullable ; structure }
end

module type NUMOPS =
sig
  type t
  type boolv
  type u8v
  val zero : t code
  val one : t code
  val of_u8v : u8v code -> t code
  val to_u8v : t code -> u8v code
  val eq : t code -> t code -> boolv code
  val ne : t code -> t code -> boolv code
  val ge : t code -> t code -> boolv code
  val gt : t code -> t code -> boolv code
  val add : t code -> t code -> t code
  val sub : t code -> t code -> t code
  val mul : t code -> t code -> t code
  val div : t code -> t code -> t code
  val rem : t code -> t code -> t code
  val shift_left : t code -> u8v code -> t code
  val shift_right : t code -> u8v code -> t code
end

module type INTREPR =
sig
  module SerData : SERDATA
  type floatv and stringv and boolv
  and i8v and i16v and i32v and i64v and i128v
  and u8v and u16v and u32v and u64v and u128v

  val length_of_stringv : stringv code -> u32v code
  val stringv_of_bytes : SerData.bytes code -> stringv code
  val bytes_of_stringv : stringv code -> SerData.bytes code

  val choose : boolv code -> 'a code -> 'a code -> 'a code
  val fst : ('a * 'b) code -> 'a code
  val snd : ('a * 'b) code -> 'b code
  val map_fst : ('a code -> 'c code) -> ('a * 'b) code -> ('c * 'b) code
  val map_pair : fst:('a code -> 'c code) -> snd:('b code -> 'd code) ->
                 ('a * 'b) code -> ('c * 'd) code

  val dword_eq : SerData.dword code -> SerData.dword code -> boolv code
  val size_ge : SerData.size code -> SerData.size code -> boolv code
  val boolv_of_const : bool -> boolv
  val boolv_and : boolv code -> boolv code -> boolv code
  val boolv_or : boolv code -> boolv code -> boolv code

  module I8 :
  sig
    include NUMOPS with type t = i8v and type boolv = boolv and type u8v = u8v
    val of_const : int -> t
    val of_boolv : boolv code -> i8v code
    val to_boolv : i8v code -> boolv code
    val of_byte : SerData.byte code -> i8v code
    val to_byte : i8v code -> SerData.byte code
  end
  module I16 :
  sig
    include NUMOPS with type t = i16v and type boolv = boolv and type u8v = u8v
    val of_const : int -> t
    val to_word : i16v code -> SerData.word code
    val of_word : SerData.word code -> i16v code
  end
  module I32 :
  sig
    include NUMOPS with type t = i32v and type boolv = boolv and type u8v = u8v
    val of_const : int32 -> t
    val of_byte : SerData.byte code -> i32v code
    val to_byte : i32v code -> SerData.byte code
    val of_size : SerData.size code -> i32v code
    val to_size : i32v code -> SerData.size code
    val to_dword : i32v code -> SerData.dword code
    val of_dword : SerData.dword code -> i32v code
  end
  module I64 :
  sig
    include NUMOPS with type t = i64v and type boolv = boolv and type u8v = u8v
    val of_const : int64 -> t
    val to_qword : i64v code -> SerData.qword code
    val of_qword : SerData.qword code -> i64v code
  end
  module I128 :
  sig
    include NUMOPS with type t = i128v and type boolv = boolv and type u8v = u8v
    val of_const : Int128.t -> t
    val to_oword : i128v code -> SerData.oword code
    val of_oword : SerData.oword code -> i128v code
  end

  module U8 :
  sig
    include NUMOPS with type t = u8v and type boolv = boolv and type u8v = u8v
    val of_const : int -> t
    val of_boolv : boolv code -> u8v code
    val to_boolv : u8v code -> boolv code
    val of_byte : SerData.byte code -> u8v code
    val to_byte : u8v code -> SerData.byte code
  end
  module U16 :
  sig
    include NUMOPS with type t = u16v and type boolv = boolv and type u8v = u8v
    val of_const : int -> t
    val to_word : u16v code -> SerData.word code
    val of_word : SerData.word code -> u16v code
  end
  module U32 :
  sig
    include NUMOPS with type t = u32v and type boolv = boolv and type u8v = u8v
    val of_const : Uint32.t -> t
    val of_byte : SerData.byte code -> u32v code
    val to_byte : u32v code -> SerData.byte code
    val of_size : SerData.size code -> u32v code
    val to_size : u32v code -> SerData.size code
    val to_dword : u32v code -> SerData.dword code
    val of_dword : SerData.dword code -> u32v code
  end
  module U64 :
  sig
    include NUMOPS with type t = u64v and type boolv = boolv and type u8v = u8v
    val of_const : Uint64.t -> t
    val to_qword : u64v code -> SerData.qword code
    val of_qword : SerData.qword code -> u64v code
  end
  module U128 :
  sig
    include NUMOPS with type t = u128v and type boolv = boolv and type u8v = u8v
    val of_const : Uint128.t -> t
    val to_oword : u128v code -> SerData.oword code
    val of_oword : SerData.oword code -> u128v code
  end

  module Float :
  sig
    val to_qword : floatv code -> SerData.qword code
    val of_qword : SerData.qword code -> floatv code
    (* Shortcut: convert between floats and string representation: *)
    val of_bytes : SerData.bytes code -> floatv code
    val to_bytes : floatv code -> SerData.bytes code
  end

  (* Peek next byte and if cond is true then accumulate it into the value. *)
  val read_while :
    cond:(SerData.byte -> boolv) code ->
    reduce:('a -> SerData.byte -> 'a) code ->
    ('a * SerData.pointer) code ->
      ('a * SerData.pointer) code

  (* Process a value of type ['a] in a loop while a condition on the loop
   * counter (of type ['b]) is true. The condition is tested initially. *)
  val do_while :
    cond:('a -> 'b -> boolv) code ->
    loop:('a -> 'b -> 'a * 'b) code ->
    'b code -> 'a code -> 'a code
end

(* Implementations must (de)serialize using only the functions above.
 * Possible implementations include:
 * - One for some user-friendly s-expression format;
 * - One for some user-friendly CSV format;
 * - One for some more efficient yet still simple binary encoding. *)

module type DES =
sig
  type pointer = IntRepr.SerData.pointer
  type 'a des = (pointer -> 'a * pointer) code

  val dfloat : IntRepr.floatv des
  val dstring : IntRepr.stringv des
  val dbool : IntRepr.boolv des
  val di8 : IntRepr.i8v des
  val di16 : IntRepr.i16v des
  val di32 : IntRepr.i32v des
  val di64 : IntRepr.i64v des
  val di128 : IntRepr.i128v des
  val du8 : IntRepr.u8v des
  val du16 : IntRepr.u16v des
  val du32 : IntRepr.u32v des
  val du64 : IntRepr.u64v des
  val du128 : IntRepr.u128v des

  val tup_opn : Type.t array -> pointer code -> pointer code
  val tup_cls : Type.t array -> pointer code -> pointer code
  val tup_sep : Type.t array -> int (* before *) -> pointer code -> pointer code
  val vec_opn : int -> Type.t -> pointer code -> pointer code
  val vec_cls : int -> Type.t -> pointer code -> pointer code
  val vec_sep : int -> Type.t -> int (* before *) -> pointer code -> pointer code

  val is_null : Type.structure -> pointer code -> IntRepr.boolv code
  val dnull : pointer code -> pointer code
  val dnotnull : pointer code -> pointer code
end

module type SER =
sig
  type pointer = IntRepr.SerData.pointer
  type 'a ser = ('a * pointer -> pointer) code

  val sfloat : IntRepr.floatv ser
  val sstring : IntRepr.stringv ser
  val sbool: IntRepr.boolv ser
  val si8 : IntRepr.i8v ser
  val si16 : IntRepr.i16v ser
  val si32 : IntRepr.i32v ser
  val si64 : IntRepr.i64v ser
  val si128 : IntRepr.i128v ser
  val su8 : IntRepr.u8v ser
  val su16 : IntRepr.u16v ser
  val su32 : IntRepr.u32v ser
  val su64 : IntRepr.u64v ser
  val su128 : IntRepr.u128v ser

  val tup_opn : Type.t array -> pointer code -> pointer code
  val tup_cls : Type.t array -> pointer code -> pointer code
  val tup_sep : Type.t array -> int (* before *) -> pointer code -> pointer code
  val vec_opn : int -> Type.t -> pointer code -> pointer code
  val vec_cls : int -> Type.t -> pointer code -> pointer code
  val vec_sep : int -> Type.t -> int (* before *) -> pointer code -> pointer code

  val snull : pointer code -> pointer code
  val snotnull : pointer code -> pointer code
end

module DesSer (Des : DES) (Ser : SER) =
struct
  let ds ser des =
    fun src dst ->
      .<
        let v, sp = .~des .~src in
        let dp = .~ser (v, .~dst) in
        sp, dp
      >.

  let dsfloat = ds Ser.sfloat Des.dfloat
  let dsstring = ds Ser.sstring Des.dstring
  let dsbool = ds Ser.sbool Des.dbool
  let dsi8 = ds Ser.si8 Des.di8
  let dsi16 = ds Ser.si16 Des.di16
  let dsi32 = ds Ser.si32 Des.di32
  let dsi64 = ds Ser.si64 Des.di64
  let dsi128 = ds Ser.si128 Des.di128
  let dsu8 = ds Ser.su8 Des.du8
  let dsu16 = ds Ser.su16 Des.du16
  let dsu32 = ds Ser.su32 Des.du32
  let dsu64 = ds Ser.su64 Des.du64
  let dsu128 = ds Ser.su128 Des.du128

  let dsnull src dst =
    .<
      .~(Des.dnull src),
      .~(Ser.snull dst)
    >.

  let dsnotnull src dst =
    .<
      .~(Des.dnotnull src),
      .~(Ser.snotnull dst)
    >.

  let rec dstup typs src dst =
    let src = Des.tup_opn typs src
    and dst = Ser.tup_opn typs dst in
    let src_dst =
      BatArray.fold_lefti (fun src_dst i typ ->
        if i = 0 then
          .< .~(desser typ) .~src_dst >.
        else
          .<
            let src, dst = .~src_dst in
            let src = .~(Des.tup_sep typs i .<src>.)
            and dst = .~(Ser.tup_sep typs i .<dst>.) in
            .~(desser typ) (src, dst)
          >.
      ) .< .~src, .~dst >. typs in
    .<
      let src, dst = .~src_dst in
      .~(Des.tup_cls typs .<src>.),
      .~(Ser.tup_cls typs .<dst>.)
    >.

  (* This will generates a long linear code with one block per array
   * item. Maybe have a IntRepr.loop instead? *)
  and dsvec dim typ src dst =
    let desser_typ = desser typ in
    let src = Des.vec_opn dim typ src
    and dst = Ser.vec_opn dim typ dst in
    let rec loop src_dst i =
      if i >= dim then
        .<
          let src, dst = .~src_dst in
          .~(Des.vec_cls dim typ .<src>.),
          .~(Ser.vec_cls dim typ .<dst>.)
        >.
      else if i = 0 then
        loop .< .~desser_typ .~src_dst >. (i + 1)
      else
        .<
          let src, dst = .~src_dst in
          let src = .~(Des.vec_sep dim typ i .<src>.)
          and dst = .~(Ser.vec_sep dim typ i .<dst>.) in
          let src_dst = .~desser_typ (src, dst) in
          .~(loop .<src_dst>. (i + 1))
        >.
    in
    loop .< .~src, .~dst >. 0

  and desser : Type.t -> (Des.pointer * Ser.pointer ->
                            Des.pointer * Ser.pointer) code = fun typ ->
    let desser_structure = function
      | Type.TFloat -> dsfloat
      | Type.TString -> dsstring
      | Type.TBool -> dsbool
      | Type.TI8 -> dsi8
      | Type.TI16 -> dsi16
      | Type.TI32 -> dsi32
      | Type.TI64 -> dsi64
      | Type.TI128 -> dsi128
      | Type.TU8 -> dsu8
      | Type.TU16 -> dsu16
      | Type.TU32 -> dsu32
      | Type.TU64 -> dsu64
      | Type.TU128 -> dsu128
      | Type.TTup typs -> dstup typs
      | Type.TVec (d, typ) -> dsvec d typ
    in
    if typ.nullable then
      .<
        fun (src, dst) ->
          .~(
            IntRepr.choose (Des.is_null typ.structure .<src>.)
              (dsnull .<src>. .<dst>.)
              .<
                let s, d = .~(dsnotnull .<src>. .<dst>.) in
                .~(desser_structure typ.structure .<s>. .<d>.)
              >.
          )
      >.
    else
      .<
        fun (src, dst) -> .~(desser_structure typ.structure .<src>. .<dst>.)
      >.
end