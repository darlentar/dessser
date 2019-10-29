open Dessser

module Ser (BE : BACKEND) : SER with module BE = BE =
struct
  module BE = BE

  type state = unit
  let init_state _typ _oc p = (), p

  type 'a ser = BE.output -> unit -> 'a -> [`Pointer] id -> [`Pointer] id

  let sfloat oc () v p = BE.ignore oc v ; p
  let sstring oc () v p = BE.ignore oc v ; p
  let sbool oc () v p = BE.ignore oc v ; p
  let si8 oc () v p = BE.ignore oc v ; p
  let su8 oc () v p = BE.ignore oc v ; p
  let si16 oc () v p = BE.ignore oc v ; p
  let su16 oc () v p = BE.ignore oc v ; p
  let si32 oc () v p = BE.ignore oc v ; p
  let su32 oc () v p = BE.ignore oc v ; p
  let si64 oc () v p = BE.ignore oc v ; p
  let su64 oc () v p = BE.ignore oc v ; p
  let si128 oc () v p = BE.ignore oc v ; p
  let su128 oc () v p = BE.ignore oc v ; p
  let tup_opn _ _ () p = p
  let tup_cls _ _ () p = p
  let tup_sep _ _ _ () p = p
  let rec_opn _ _ () p = p
  let rec_cls _ _ () p = p
  let rec_sep _ _ _ () p = p
  let vec_opn _ _ _ () p = p
  let vec_cls _ _ _ () p = p
  let vec_sep _ _ _ _ () p = p
  let nullable _ _ () p = p
  let snull _ () p = p
  let snotnull _ () p = p
end
