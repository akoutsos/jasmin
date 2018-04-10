(* -------------------------------------------------------------------- *)
open Prog

module E = Expr
module F = Format
module B = Bigint

(* -------------------------------------------------------------------- *)
let rec pp_list sep pp fmt xs =
  let pp_list = pp_list sep pp in
    match xs with
    | []      -> ()
    | [x]     -> Format.fprintf fmt "%a" pp x
    | x :: xs -> Format.fprintf fmt "%a%(%)%a" pp x sep pp_list xs

(* -------------------------------------------------------------------- *)
let pp_iloc fmt (l,ls) =
  Format.fprintf fmt "@[%a@]" (pp_list " from@ " L.pp_sloc) (l::ls)

(* -------------------------------------------------------------------- *)
let pp_string0 fmt str =
  F.fprintf fmt "%a" (pp_list "" F.pp_print_char) str

(* -------------------------------------------------------------------- *)
let pp_bool fmt b =
  if b then F.fprintf fmt "true"
  else F.fprintf fmt "false"

(* -------------------------------------------------------------------- *)
let pp_btype fmt = function
  | Bool -> F.fprintf fmt "bool"
  | U i  -> F.fprintf fmt "U%i" (int_of_ws i)
  | Int  -> F.fprintf fmt "int"

(* -------------------------------------------------------------------- *)
let pp_gtype (pp_size:F.formatter -> 'size -> unit) fmt = function
  | Bty ty -> pp_btype fmt ty
  | Arr(ws,e) -> F.fprintf fmt "%a[%a]" pp_btype (U ws) pp_size e

(* -------------------------------------------------------------------- *)
let pp_gvar_i pp_var fmt v = pp_var fmt (L.unloc v)

(* -------------------------------------------------------------------- *)

let string_of_cmp_ty = function
  | E.Cmp_w (Type.Unsigned, _) -> "u"
  | _        -> ""

let string_of_op2 = function
  | E.Oand   -> "&&"
  | E.Oor    -> "||"
  | E.Oadd _ -> "+"
  | E.Omul _ -> "*"
  | E.Osub _ -> "-"

  | E.Oland _ -> "&"
  | E.Olor _ -> "|"
  | E.Olxor _ -> "^"
  | E.Olsr _ -> ">>"
  | E.Olsl _ -> "<<"
  | E.Oasr _ -> ">>s"

  | E.Oeq  _ -> "=="
  | E.Oneq _ -> "!="
  | E.Olt  k -> "<"  ^ string_of_cmp_ty k
  | E.Ole  k -> "<=" ^ string_of_cmp_ty k
  | E.Ogt  k -> ">"  ^ string_of_cmp_ty k
  | E.Oge  k -> ">=" ^ string_of_cmp_ty k

let pp_op1 = function
  | E.Olnot _ -> "!"
  | E.Onot    -> "~"
  | E.Oneg _ -> "-"
  | E.Oarr_init _ -> "array_init"

(* -------------------------------------------------------------------- *)
let pp_ge pp_var =
  let pp_var_i = pp_gvar_i pp_var in
  let rec pp_expr fmt = function
  | Pconst i    -> B.pp_print fmt i
  | Pbool  b    -> F.fprintf fmt "%b" b
  | Pcast(ws,e) -> F.fprintf fmt "(%a)%a" pp_btype (U ws) pp_expr e
  | Pvar v      -> pp_var_i fmt v
  | Pglobal g -> F.fprintf fmt "%s" g
  | Pget(x,e)   -> F.fprintf fmt "%a[%a]" pp_var_i x pp_expr e
  | Pload(ws,x,e) ->
    F.fprintf fmt "@[(load %a@ %a@ %a)@]"
      pp_btype (U ws) pp_var_i x pp_expr e
  | Papp1(o, e) ->
    F.fprintf fmt "@[(%s@ %a)@]" (pp_op1 o) pp_expr e
  | Papp2(op,e1,e2) ->
    F.fprintf fmt "@[(%a %s@ %a)@]"
      pp_expr e1 (string_of_op2 op) pp_expr e2
  | Pif(e,e1,e2) ->
    F.fprintf fmt "@[(%a ?@ %a :@ %a)@]"
      pp_expr e pp_expr e1  pp_expr e2
  in
  pp_expr

(* -------------------------------------------------------------------- *)
let pp_glv pp_var fmt = function
  | Lnone _ -> F.fprintf fmt "_"
  | Lvar x  -> pp_gvar_i pp_var fmt x
  | Lmem (ws, x, e) ->
    F.fprintf fmt "@[store %a@ %a@ %a@]"
     pp_btype (U ws) (pp_gvar_i pp_var) x (pp_ge pp_var) e
  | Laset(x,e) ->
    F.fprintf fmt "%a[%a]" (pp_gvar_i pp_var) x (pp_ge pp_var) e

(* -------------------------------------------------------------------- *)
let pp_ges pp_var fmt es =
  Format.fprintf fmt "@[%a@]" (pp_list ",@ " (pp_ge pp_var)) es

(* -------------------------------------------------------------------- *)
let pp_glvs pp_var fmt lvs =
  match lvs with
  | [] -> F.fprintf fmt "()"
  | [x] -> pp_glv pp_var fmt x
  | _   -> F.fprintf fmt "(@[%a@])" (pp_list ",@ " (pp_glv pp_var)) lvs

(* -------------------------------------------------------------------- *)
let pp_opn =
  let open Expr in
  function
  | Omulu _      -> "#mulu"
  | Oaddcarry _  -> "#addc"
  | Osubcarry _  -> "#subc"
  | Oset0 _      -> "#set0"
  | Ox86_MOV _   -> "#x86_MOV"
  | Ox86_CMOVcc _ -> "#x86_CMOVcc"
  | Ox86_ADD _   -> "#x86_ADD"
  | Ox86_SUB _   -> "#x86_SUB"
  | Ox86_MUL _   -> "#x86_MUL"
  | Ox86_IMUL _  -> "#x86_IMUL"
  | Ox86_IMULt _ -> "#x86_IMUL64"
  | Ox86_IMULtimm _ -> "#x86_IMUL64imm"
  | Ox86_DIV _   -> "#x86_DIV"
  | Ox86_IDIV _  -> "#x86_IDIV"
  | Ox86_ADC _   -> "#x86_ADC"
  | Ox86_SBB _   -> "#x86_SBB"
  | Ox86_NEG _ -> "#x86_NEG"
  | Ox86_INC _   -> "#x86_INC"
  | Ox86_DEC _   -> "#x86_DEC"
  | Ox86_SETcc   -> "#x86_SETcc"
  | Ox86_BT _ -> "#x86_BT"
  | Ox86_LEA _   -> "#x86_LEA"
  | Ox86_TEST _  -> "#x86_TEST"
  | Ox86_CMP _   -> "#x86_CMP"
  | Ox86_AND _   -> "#x86_AND"
  | Ox86_OR _    -> "#x86_OR"
  | Ox86_XOR _   -> "#x86_XOR"
  | Ox86_NOT _   -> "#x86_NOT"
  | Ox86_ROL _ -> "#x86_ROL"
  | Ox86_ROR _ -> "#x86_ROR"
  | Ox86_SHL _   -> "#x86_SHL"
  | Ox86_SHR _   -> "#x86_SHR"
  | Ox86_SAR _   -> "#x86_SAR"
  | Ox86_SHLD _  -> "#x86_SHLD"

(* -------------------------------------------------------------------- *)
let pp_tag = function
  | AT_none    -> ""
  | AT_keep    -> ":k"
  | AT_rename  -> ":r"
  | AT_inline  -> ":i"
  | AT_phinode -> ":φ"

let rec pp_gi pp_info pp_var fmt i =
  F.fprintf fmt "%a" pp_info i.i_info;
  match i.i_desc with
  | Cblock c ->
    F.fprintf fmt "@[<v>{@   @[<v>%a@]@ }@]" (pp_cblock pp_info pp_var) c

  | Cassgn(x , tg, ty, e) -> (* FIXME: ty *)
    F.fprintf fmt "@[<hov 2>%a %s=@ %a;@]"
      (pp_glv pp_var) x (pp_tag tg) (pp_ge pp_var) e

  | Copn(x, t, o, e) -> (* FIXME *)
    F.fprintf fmt "@[<hov 2>%a %s=@ %s(%a);@]"
       (pp_glvs pp_var) x (pp_tag t) (pp_opn o)
       (pp_ges pp_var) e

  | Cif(e, c, []) ->
    F.fprintf fmt "@[<v>if %a %a@]"
      (pp_ge pp_var) e (pp_cblock pp_info pp_var) c

  | Cif(e, c1, c2) ->
    F.fprintf fmt "@[<v>if %a %a else %a@]"
      (pp_ge pp_var) e (pp_cblock pp_info pp_var) c1
      (pp_cblock pp_info pp_var) c2

  | Cfor(i, (dir, lo, hi), c) ->
    let dir, e1, e2 =
      if dir = UpTo then "to", lo, hi else "downto", hi, lo in
    F.fprintf fmt "@[<v>for %a = @[%a %s@ %a@] %a@]"
      (pp_gvar_i pp_var) i (pp_ge pp_var) e1 dir (pp_ge pp_var) e2
      (pp_gc pp_info pp_var) c

  | Cwhile([], e, c) ->
    F.fprintf fmt "@[<v>while (%a) %a@]"
      (pp_ge pp_var) e (pp_cblock pp_info pp_var) c

  | Cwhile(c, e, []) ->
    F.fprintf fmt "@[<v>while %a (%a)@]"
      (pp_cblock pp_info pp_var) c (pp_ge pp_var) e

  | Cwhile(c, e, c') ->
    F.fprintf fmt "@[<v>while %a %a %a@]"
      (pp_cblock pp_info pp_var) c (pp_ge pp_var) e
      (pp_cblock pp_info pp_var) c'

  | Ccall(_ii, x, f, e) -> (* FIXME ii *)
    F.fprintf fmt "@[<hov 2> %a =@ %s(%a);@]"
      (pp_glvs pp_var) x f.fn_name (pp_ges pp_var) e

(* -------------------------------------------------------------------- *)
and pp_gc pp_info pp_var fmt c =
  F.fprintf fmt "@[<v>%a@]" (pp_list "@ " (pp_gi pp_info pp_var)) c

(* -------------------------------------------------------------------- *)
and pp_cblock pp_info pp_var fmt c =
  F.fprintf fmt "{@   %a@ }" (pp_gc pp_info pp_var) c

(* -------------------------------------------------------------------- *)

let pp_kind fmt = function
  | Const  ->  F.fprintf fmt "Const"
  | Stack  ->  F.fprintf fmt "Stack"
  | Reg    ->  F.fprintf fmt "Reg"
  | Inline ->  F.fprintf fmt "Inline"
  | Global ->  F.fprintf fmt "Global"

let pp_ty_decl (pp_size:F.formatter -> 'size -> unit) fmt v =
  F.fprintf fmt "%a %a" pp_kind v.v_kind (pp_gtype pp_size) v.v_ty

let pp_var_decl pp_var pp_size fmt v =
  F.fprintf fmt "%a %a" (pp_ty_decl pp_size) v pp_var v

let pp_gfun pp_info (pp_size:F.formatter -> 'size -> unit) pp_var fmt fd =
  let pp_vd =  pp_var_decl pp_var pp_size in
(*  let locals = locals fd in *)
  let ret = List.map L.unloc fd.f_ret in
  let pp_ret fmt () =
    F.fprintf fmt "return @[(%a)@];"
      (pp_list ",@ " pp_var) ret in

  F.fprintf fmt "@[<v>fn %s @[(%a)@] -> @[(%a)@] {@   @[<v>%a@ %a@]@ }@]"
   fd.f_name.fn_name
   (pp_list ",@ " pp_vd) fd.f_args
   (pp_list ",@ " (pp_ty_decl pp_size)) ret
(*   (pp_list ";@ " pp_vd) (Sv.elements locals) *)
   (pp_gc pp_info pp_var) fd.f_body
   pp_ret ()

let pp_noinfo _ _ = ()

let pp_pitem pp_var =
  let pp_size = pp_ge pp_var in
  let aux fmt = function
    | MIfun fd -> pp_gfun pp_noinfo pp_size pp_var fmt fd
    | MIglobal (x, e)
    | MIparam (x,e) ->
      F.fprintf fmt "%a = %a"
        (pp_var_decl pp_var pp_size) x
        (pp_ge pp_var) e in
  aux

let pp_pvar fmt x = F.fprintf fmt "%s" x.v_name 

let pp_ptype =
  let pp_size = pp_ge pp_pvar in
  pp_gtype pp_size

let pp_plval = 
  pp_glv pp_pvar 

let pp_pexpr =
  pp_ge pp_pvar 

let pp_pprog fmt p =
  Format.fprintf fmt "@[<v>%a@]"
    (pp_list "@ @ " (pp_pitem pp_pvar)) (List.rev p)


let pp_fun ?(pp_info=pp_noinfo) pp_var fmt fd =
  let pp_size fmt i = F.fprintf fmt "%i" i in
  let pp_vd =  pp_var_decl pp_var pp_size in
  let locals = locals fd in
  let ret = List.map L.unloc fd.f_ret in
  let pp_ret fmt () =
    F.fprintf fmt "return @[(%a)@];"
      (pp_list ",@ " pp_var) ret in

  F.fprintf fmt "@[<v>fn %s @[(%a)@] -> @[(%a)@] {@   @[<v>%a@ %a@ %a@]@ }@]"
   fd.f_name.fn_name
   (pp_list ",@ " pp_vd) fd.f_args
   (pp_list ",@ " (pp_ty_decl pp_size)) ret
   (pp_list ";@ " pp_vd) (Sv.elements locals)
   (pp_gc pp_info pp_var) fd.f_body
   pp_ret ()

let pp_var ~debug =
    if debug then
      fun fmt x -> F.fprintf fmt "%s.%i" x.v_name (int_of_uid x.v_id)
    else
      fun fmt x -> F.fprintf fmt "%s" x.v_name


let pp_expr ~debug fmt e =
  let pp_var = pp_var ~debug in
  pp_ge pp_var fmt e

let pp_instr ~debug fmt i =
  let pp_var = pp_var ~debug in
  pp_gi pp_noinfo pp_var fmt i

let pp_stmt ~debug fmt i =
  let pp_var = pp_var ~debug in
  pp_gc pp_noinfo pp_var fmt i

let pp_ifunc ~debug pp_info fmt fd =
  let pp_var = pp_var ~debug in
  pp_fun ~pp_info pp_var fmt fd

let pp_func ~debug fmt fd =
  let pp_var = pp_var ~debug in
  pp_fun pp_var fmt fd

let pp_prog ~debug fmt p =
  let pp_var = pp_var ~debug in
  Format.fprintf fmt "@[<v>%a@]"
     (pp_list "@ @ " (pp_fun pp_var)) (List.rev p)

let pp_iprog ~debug pp_info fmt p =
  let pp_var = pp_var ~debug in
  Format.fprintf fmt "@[<v>%a@]"
     (pp_list "@ @ " (pp_fun ~pp_info pp_var)) (List.rev p)

let pp_prog ~debug fmt p =
  let pp_var = pp_var ~debug in
  Format.fprintf fmt "@[<v>%a@]"
     (pp_list "@ @ " (pp_fun pp_var)) (List.rev p)


(* ----------------------------------------------------------------------- *)

let pp_warning_msg fmt = function
  | Compiler_util.Use_lea -> Format.fprintf fmt "LEA instruction is used"
      
(*
let pp_cprog fmt p =
  let open Expr in
  let string_cmp_ty = function
    | Cmp_int -> "i"
    | Cmp_uw  -> "u"
    | Cmp_sw  -> "s" in

  let pp_pos fmt n =
    Format.fprintf fmt "%a" B.pp_print (Conv.bi_of_pos n) in
  let pp_var fmt v =
    Format.fprintf fmt "%s" (Conv.string_of_string0 v.Var0.Var.vname) in
  let pp_vari fmt v =
    pp_var fmt (v.Expr.v_var) in
  let pp_op2 = function
    | Oand -> "&&"
    | Oor  -> "||"
    | Oadd _ -> "+"
    | Omul _ -> "*"
    | Osub _ -> "-"
    | Oeq  k -> "==" ^ string_cmp_ty k
    | Oneq k -> "!=" ^ string_cmp_ty k
    | Olt  k -> "<"  ^ string_cmp_ty k
    | Ole  k -> "<=" ^ string_cmp_ty k
    | Ogt  k -> ">"  ^ string_cmp_ty k
    | Oge  k -> ">=" ^ string_cmp_ty k
    | Oland  -> "&"
    | Olor   -> "|"
    | Olxor  -> "^"
    | Olsr   -> ">>"
    | Olsl   -> "<<"
    | Oasr   -> ">>s"

  in
  let rec pp_expr fmt = function
    | Pconst z -> Format.fprintf fmt "%a" B.pp_print (Conv.bi_of_z z)
    | Pbool b  -> pp_bool fmt b
    | Pcast e  -> Format.fprintf fmt "(u64)%a" pp_expr e
    | Pvar  v  -> pp_vari fmt v
    | Pget(v,e) -> Format.fprintf fmt "%a[%a]" pp_vari v pp_expr e
    | Pload(v,e) -> Format.fprintf fmt "(load %a %a)" pp_vari v pp_expr e
    | Papp1(_o, e) -> Format.fprintf fmt "(! %a)" pp_expr e
    | Papp2(o,e1,e2) ->
      Format.fprintf fmt "(%a %s %a)" pp_expr e1 (pp_op2 o) pp_expr e2
    | Pif (e,e1,e2) ->
      Format.fprintf fmt "(%a ? %a : %a)" pp_expr e pp_expr e1 pp_expr e2
  in

  let pp_exprs fmt = Format.fprintf fmt "@[%a@]" (pp_list ",@ " pp_expr) in

  let pp_lval fmt = function
    | Lnone _ -> Format.fprintf fmt "_"
    | Lvar x  -> pp_vari fmt x
    | Lmem(x,e) -> Format.fprintf fmt "(store %a %a)" pp_vari x pp_expr e
    | Laset(x,e) -> Format.fprintf fmt "%a[%a]" pp_vari x pp_expr e in

  let pp_lvals fmt = Format.fprintf fmt "@[%a@]" (pp_list ",@ " pp_lval) in

  let pp_tag = function
    | AT_keep       -> ""
    | AT_rename_arg -> ":a"
    | AT_rename_res -> ":r"
    | AT_inline     -> ":i" in

  let pp_sop = function
    | Olnot     -> "Olnot"
    | Oxor      -> "Oxor"
    | Oland     -> "Oland"
    | Olor      -> "Olor"
    | Olsr      -> "Olsr"
    | Olsl      -> "Olsl"
    | Oif       -> "Oif"
    | Omulu     -> "Omulu"
    | Omuli     -> "Omuli"
    | Oaddcarry -> "Oaddcarry"
    | Osubcarry -> "Osubcarry"
    | Oleu      -> "Oleu"
    | Oltu      -> "Oltu"
    | Ogeu      -> "Ogeu"
    | Ogtu      -> "Ogtu"
    | Oles      -> "Oles"
    | Olts      -> "Olts"
    | Oges      -> "Oges"
    | Ogts      -> "Ogts"
    | Oeqw      -> "Oeqw" in

  let rec pp_instr fmt (MkI(_, i)) =
    match i with
    | Cassgn(x,t,e) ->
      Format.fprintf fmt "%a %s= %a;" pp_lval x (pp_tag t) pp_expr e
    | Copn(x,o,e) ->
      Format.fprintf fmt "%a = #%s(%a);" pp_lvals x (pp_sop o) pp_exprs e
    | Cif(e, c1, c2) ->
      Format.fprintf fmt "if %a {@   @[<v>%a@]@ } else {@   @[<v>%a@]@ }"
        pp_expr e pp_cmd c1 pp_cmd c2
    | Cfor(x,((dir, e1), e2), c) ->
      let s, e1, e2 =
        if dir = UpTo then "to", e1, e2 else "downto", e2, e1 in
      Format.fprintf fmt "for %a = %a %s %a {@   @[<v>%a@]@ }"
        pp_vari x pp_expr e1 s pp_expr e2 pp_cmd c
    | Cwhile(c1, e, c2) ->
      Format.fprintf fmt "while {@   @[<v>%a@]@ }(%a){@   @[<v>%a@]@ }"
        pp_cmd c1 pp_expr e pp_cmd c2
    | Ccall(_, x, f, e) ->
      Format.fprintf fmt "%a = %a(%a);" pp_lvals x pp_pos f pp_exprs e

  and pp_cmd fmt c = pp_list "@ " pp_instr fmt c in

  let pp_params xs = pp_list ", " pp_vari xs in

  let pp_res xs = pp_list ", " pp_vari xs in

  let pp_cfun fmt (n,fd) =
    Format.fprintf fmt "fn %a(%a) {@  @[<v>%a@]@ return %a;@ }@ @ "
      pp_pos n
      pp_params fd.f_params
      pp_cmd fd.f_body
      pp_res fd.f_res in
  Format.fprintf fmt "@[<v>%a@]" (pp_list "@ @ " pp_cfun) p
 *)
