open Batteries
open Stdint
open Dessser
open DessserTools
open DessserDSTools
module T = DessserTypes
module E = DessserExpressions
open E.Ops

let run_cmd cmd =
  match Unix.system cmd with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED code ->
      Printf.sprintf "%s failed with code %d\n" cmd code |>
      failwith
  | Unix.WSIGNALED s ->
      Printf.sprintf "%s killed with signal %d" cmd s |>
      failwith
  | Unix.WSTOPPED s ->
      Printf.sprintf "%s stopped by signal %d" cmd s |>
      failwith

let () =
  let m x = T.{ vtyp = Mac x ; nullable = false }
  and n x = T.{ vtyp = Mac x ; nullable = true } in
  let udp_typ =
    T.make (TTup [|
      m TString ; m TU64 ; m TU64 ; m TU8 ; m TString ; m TU8 ; m TString ; n TU32 ;
      n TU32 ; m TU64 ; m TU64 ; m TU32 ; m TU32 ; n TU32 ; n TString ; n TU32 ;
      n TString ; n TU32 ; n TString ; m TU16 ; m TU16 ; m TU8 ; m TU8 ; n TU32 ;
      n TU32 ; m TU32 ; m TString ; m TU64 ; m TU64 ; m TU64 ; (* Should be U32 *)
      m TU64 ; (* Should be U32 *) m TU64 ; m TU64 ; n TString
    |])
  and _http_typ =
    T.make (TTup [|
      m TString ; m TU64 ; m TU64 ; m TU8 ; m TString ; m TU8 ; m TString ;
      n TU32 ; n TU32 ; m TU64 ; m TU64 ; m TU32 ; m TU32 ;
      n TU32 ; T.maken (TVec (16, m TChar)) ;
      n TU32 ; T.maken (TVec (16, m TChar)) ;
      m TU16 ; m TU16 ; m TU128 ; m TU128 ; m TU128 ; n TU128 ;
      m TU8 ; m TU8 ; m TU8 ; n TString ; n TString ;
      n TString (* url *) ; n TString ; m TU8 ; m TU8 ; m TU8 ;
      n TU32 ; T.maken (TVec (16, m TChar)) ;
      m TU8 ; m TU8 ; m TU64 ; m TU64 ; m TU8 ; m TU32 ; m TU32 ; m TU32 ;
      n TString ; m TU32 ; m TU8 ; n TString ;
      n TU64 ; n TU64 ; n TU32 ;
      m TU32 ; m TU32 ; m TU32 ;
      n TString ; m TU32 ; m TU8 ; n TString ;
      m TU32 ; m TU32 ; m TU16 ; m TU16 ; m TU16 ;
      m TU64 ; m TU64 ; m TU64 ; m TFloat ; m TU8 ; m TI64 ; m TFloat ;
      m TI64 ; m TFloat ; m TI64 ; m TFloat ; m TU32 |]) in
  let typ = udp_typ in
  let backend, exe_ext =
    if Array.length Sys.argv > 1 && Sys.argv.(1) = "ocaml" then
      (module BackEndOCaml : BACKEND), ".opt"
    else if Array.length Sys.argv > 1 && Sys.argv.(1) = "c++" then
      (module BackEndCPP : BACKEND), ".exe"
    else (
      Printf.eprintf "%s ocaml|c++\n" Sys.argv.(0) ;
      exit 1
    ) in
  let module BE = (val backend : BACKEND) in
  let convert_only = false in
  let convert =
    if convert_only then (
      (* Just convert the rowbinary to s-expr: *)
      let module DS = DesSer (RowBinary.Des) (SExpr.Ser) in
      E.func2 TDataPtr TDataPtr (fun _l src dst ->
        comment "Convert from RowBinary into S-Expression:"
          (DS.desser typ src dst))
    ) else (
      (* convert from RowBinary into a heapvalue, compute its serialization
       * size in RamenringBuf format, then convert it into S-Expression: *)
      let module ToValue = HeapValue.Materialize (RowBinary.Des) in
      (* To compute sersize in RingBuffer: *)
      let module OfValue1 = HeapValue.Serialize (RamenRingBuffer.Ser) in
      (* To serialize into S-Expr: *)
      let module OfValue2 = HeapValue.Serialize (SExpr.Ser) in

      let ma = copy_field in
      E.func2 TDataPtr TDataPtr (fun _l src dst ->
        comment "Convert from RowBinary into a heap value:" (
          let v_src = ToValue.make typ src in
          E.with_sploded_pair "v_src" v_src (fun v src ->
            comment "Compute the serialized size of this tuple:" (
              let const_dyn_sz = OfValue1.sersize typ ma v in
              E.with_sploded_pair "read_tuple" const_dyn_sz (fun const_sz dyn_sz ->
                seq [
                  dump (string "Constant size: ") ;
                  dump const_sz ;
                  dump (string ", dynamic size: ") ;
                  dump dyn_sz ;
                  dump (string "\n") ;
                  comment "Now convert the heap value into an SExpr:" (
                    let dst' = OfValue2.serialize typ ma v dst in
                    pair src dst') ])))))
    ) in
  (*Printf.printf "convert = %a\n%!" (print_expr ?max_depth:None) convert ;*)
  let exe_fname = "examples/rowbinary2sexpr"^ exe_ext in
  let exe_fname = make_converter ~exe_fname backend convert in
  Printf.printf "executable in %s" exe_fname
