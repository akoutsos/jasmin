(* -------------------------------------------------------------------- *)
exception InvalidRegSize of Low_memory.wsize

(* -------------------------------------------------------------------- *)
val pp_instr : X86.instr -> string