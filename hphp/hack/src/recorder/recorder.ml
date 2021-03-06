open Recorder_types

let file_extension = "hrec"

(** Do something with the events when flushing the buffer. *)
type transcriber =
  (** The unix path of the file to transcribe to. *)
  | Transcribe_to_file of string
  (** Call this consumer when transcribing the events. *)
  | Transcribe_to_consumer : ((event list) -> unit) -> transcriber

type init_settings = {
  transcriber: transcriber;
}

type start_env = {
  (** Unix.timeofday of when recording was switched on. *)
  start_time : float;
  settings : init_settings;
}

type env = {
  start_env : start_env;
  (** Reversed list of events. i.e., the most-recent event is first in the
   * list. *)
  rev_buffered_recording: event list;
}

type instance =
  | Switched_off
  (** Recording is about to start but is pending a fresh version control state
   * to start actively recording.
   *
   * Note: We don't start recording after init completes because init
   * does not imply that the working directory is in a fresh
   * state. We truly want the VCS to move to a fresh SHA. *)
  | Pending_start of start_env
  | Active of env

let describe_transcriber transcriber = match transcriber with
  | Transcribe_to_file path -> path
  | Transcribe_to_consumer _ -> "Transcribe_to_consumer"

let flush_to_transcriber transcriber events = match transcriber with
  | Transcribe_to_file _ ->
    (** TODO *)
    ()
  | Transcribe_to_consumer f ->
    f events

let log_start init_settings =
  Hh_logger.log "Starting recorder with transcriber: %s"
    (describe_transcriber init_settings.transcriber)

let start init_settings =
  let start = Unix.gettimeofday () in
  let () = log_start init_settings in
  Pending_start ({ start_time = start; settings = init_settings; })

let default_instance = Switched_off

let flush_recording env =
  flush_to_transcriber env.start_env.settings.transcriber
    (List.rev env.rev_buffered_recording)

let with_event event env =
  { env with rev_buffered_recording = event :: env.rev_buffered_recording; }

let init_active_from_fresh_vcs_state start_env state_name =
  Active {
    start_env = start_env;
    rev_buffered_recording = [Fresh_vcs_state state_name]; }

let add_event event instance = match instance, event with
  | Pending_start start_env, Fresh_vcs_state state_name ->
    init_active_from_fresh_vcs_state start_env state_name
  | Pending_start _, _ ->
    (** Ignore while we're waiting for a fresh VCS state. *)
    instance
  | Switched_off, _ ->
    instance
  | Active env, Stop_recording ->
    let () = flush_recording env in
    Switched_off
  | Active env, _ ->
    let env = with_event event env in
    Active env
