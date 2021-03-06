(**
 * Copyright (c) 2015, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the "hack" directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 *)

(*****************************************************************************)
(* Types, constants *)
(*****************************************************************************)

type options = {
  filename : string;
  is_test : bool;
  read_stdin : bool;
}

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let die str =
  let oc = stderr in
  output_string oc str;
  close_out oc;
  exit 2

let parse_options () =
  let fn_ref = ref None in
  let is_test_ref = ref false in
  let read_stdin_ref = ref false in

  let usage = Printf.sprintf "Usage: %s filename\n" Sys.argv.(0) in
  let set_flag x () = x := true in

  let options = [
    "--test",
      Arg.Unit (set_flag is_test_ref),
      "Emit a call to test() in the file's pseudomain (for testing)";
    "--stdin",
      Arg.Unit (set_flag read_stdin_ref),
      "Read the input code from stdin instead of from the file; " ^
        "(filename still required for debug info etc)";
  ] in
  Arg.parse options (fun fn -> fn_ref := Some fn) usage;
  let fn = match !fn_ref with
    | Some fn -> fn
    | None -> die usage in
  { filename = fn;
    is_test = !is_test_ref;
    read_stdin = !read_stdin_ref;
  }

(*****************************************************************************)
(* Main body *)
(*****************************************************************************)
let emit_file { filename; read_stdin; is_test } () =
  let filename = Relative_path.create Relative_path.Dummy filename in
  let contents =
    if read_stdin then Sys_utils.read_stdin_to_string () else
      Sys_utils.cat (Relative_path.to_absolute filename) in

  (* Parse the file and pull out the parts we need *)
  let parsed_file =
    Parser_hack.program_with_default_popt filename contents  in
  let {Parser_hack.file_mode; comments; ast; _} = parsed_file in
  let funs, classes, typedefs, consts = Ast_utils.get_defs ast in

  if file_mode <> Some FileInfo.Mstrict &&
     file_mode <> Some FileInfo.Mpartial then
    die "Can only emit files in strict/partial mode\n";

  Parser_heap.ParserHeap.add filename (ast, Parser_heap.Full);

  (* Build a naming environment and run naming *)
  let tcopt = TypecheckerOptions.default in
  NamingGlobal.make_env ~funs ~classes ~typedefs ~consts;

  (* Actually emit. *)
  Emitter.emit_file ~is_test tcopt filename ast


let main_hack options =
  EventLogger.init EventLogger.Event_logger_fake 0.0;
  let _handle = SharedMem.init GlobalConfig.default_sharedmem_config in

  (* The emitter needs to track the names of identifiers in order to
   * preserve the names in the output bytecode. *)
  Local_id.track_names := true;

  (* Wrap everything with error ignoring; we have "strict mode hack"
   * as a precondition for the emitter but there will likely be naming
   * errors when emitting a file from a project. *)
  Errors.ignore_ (emit_file options)


(* command line driver *)
let _ =
  if ! Sys.interactive
  then ()
  else
    let options = parse_options () in
    main_hack options
