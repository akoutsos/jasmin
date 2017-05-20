(* ** License
 * -----------------------------------------------------------------------
 * Copyright 2016--2017 IMDEA Software Institute
 * Copyright 2016--2017 Inria
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 * ----------------------------------------------------------------------- *)

From mathcomp Require Import all_ssreflect.
Require Import Utf8.
Require Import expr.

Section LOWERING.

Record fresh_vars : Type :=
  {
    fresh_OF : Equality.sort Ident.ident;
    fresh_CF : Equality.sort Ident.ident;
    fresh_SF : Equality.sort Ident.ident;
    fresh_PF : Equality.sort Ident.ident;
    fresh_ZF : Equality.sort Ident.ident;

    fresh_multiplicand : Equality.sort Ident.ident;
  }.

Context (fv: fresh_vars).

Definition var_info_of_lval (x: lval) : var_info :=
  match x with 
  | Lnone i t => i
  | Lvar x | Lmem _ x _ | Laset x _ => v_info x
  end.

Definition stype_of_lval (x: lval) : stype :=
  match x with
  | Lnone _ t => t
  | Lvar v | Lmem _ v _ | Laset v _ => v.(vtype)
  end.

Variant lower_cond1 :=
  | CondVar
  | CondNotVar.

Variant lower_cond2 :=
  | CondEq
  | CondNeq
  | CondOr
  | CondAndNot.

Variant lower_cond3 :=
  | CondOrNeq
  | CondAndNotEq.

Variant lower_cond_t : Type :=
  | Cond1 of lower_cond1 & var_i
  | Cond2 of lower_cond2 & var_i & var_i
  | Cond3 of lower_cond3 & var_i & var_i & var_i.

Definition lower_cond_classify vi (e: pexpr) :=
  let nil := Lnone vi sbool in
  let fr n := {| v_var := {| vtype := sbool; vname := n fv |} ; v_info := vi |} in
  let vof := fr fresh_OF in
  let vcf := fr fresh_CF in
  let vsf := fr fresh_SF in
  let vpf := fr fresh_PF in
  let vzf := fr fresh_ZF in
  let lof := Lvar vof in
  let lcf := Lvar vcf in
  let lsf := Lvar vsf in
  let lpf := Lvar vpf in
  let lzf := Lvar vzf in
  match e with
  | Papp2 op x y =>
    match op with
    | Oeq (Cmp_sw ws | Cmp_uw ws) =>
      Some ([:: nil ; nil ; nil ; nil ; lzf ], ws, Cond1 CondVar vzf, x, y)
    | Oneq (Cmp_sw ws | Cmp_uw ws) =>                   
      Some ([:: nil ; nil ; nil ; nil ; lzf ], ws, Cond1 CondNotVar vzf, x, y)
    | Olt (Cmp_sw ws) =>                                
      Some ([:: lof ; nil ; lsf ; nil ; nil ], ws, Cond2 CondNeq vsf vof, x, y)
    | Olt (Cmp_uw ws) =>                                
      Some ([:: nil ; lcf ; nil ; nil ; nil ], ws, Cond1 CondVar vcf, x, y)
    | Ole (Cmp_sw ws) =>                                
      Some ([:: lof ; nil ; lsf ; nil ; lzf ], ws, Cond3 CondOrNeq vzf vsf vof, x, y)
    | Ole (Cmp_uw ws) =>                                
      Some ([:: nil ; lcf ; nil ; nil ; lzf ], ws, Cond2 CondOr vcf vzf, x, y)
    | Ogt (Cmp_sw ws) =>                                
      Some ([:: lof ; nil ; lsf ; nil ; lzf ], ws, Cond3 CondAndNotEq vzf vsf vof, x, y)
    | Ogt (Cmp_uw ws) =>                                
      Some ([:: nil ; lcf ; nil ; nil ; lzf ], ws, Cond2 CondAndNot vcf vzf, x, y)
    | Oge (Cmp_sw ws) =>                                
      Some ([:: lof ; nil ; lsf ; nil ; nil ], ws, Cond2 CondEq vsf vof, x, y)
    | Oge (Cmp_uw ws) =>                               
      Some ([:: nil ; lcf ; nil ; nil ; nil ], ws, Cond1 CondNotVar vcf, x, y)
    | _ => None
    end
  | _ => None
  end.

Definition eq_f  v1 v2 := Pif (Pvar v1) (Pvar v2) (Papp1 Onot (Pvar v2)).
Definition neq_f v1 v2 := Pif (Pvar v1) (Papp1 Onot (Pvar v2)) (Pvar v2).

Definition lower_condition vi (pe: pexpr) : seq instr_r * pexpr :=
  match lower_cond_classify vi pe with
  | Some (l, ws, r, x, y) =>
    ([:: Copn l (Ox86_CMP ws) [:: x; y] ],
    match r with
    | Cond1 CondVar v => Pvar v
    | Cond1 CondNotVar v => Papp1 Onot (Pvar v)
    | Cond2 CondEq v1 v2 => eq_f v1 v2
    | Cond2 CondNeq v1 v2 => neq_f v1 v2
    | Cond2 CondOr v1 v2 => Papp2 Oor v1 v2
    | Cond2 CondAndNot v1 v2 => Papp2 Oand (Papp1 Onot (Pvar v1)) (Papp1 Onot (Pvar v2))
    | Cond3 CondOrNeq v1 v2 v3 => Papp2 Oor v1 (neq_f v2 v3)
    | Cond3 CondAndNotEq v1 v2 v3 => Papp2 Oand (Papp1 Onot v1) (eq_f v2 v3)
    end)
  | None => ([::], pe)
  end.

(* Lowering of Cassgn
*)

Variant add_inc_dec : Type :=
  | AddInc of pexpr
  | AddDec of pexpr
  | AddNone.

Definition add_inc_dec_classify (a: pexpr) (b: pexpr) :=
  match a, b with
  | Pcast _ (Pconst 1), y    | y, Pcast _ (Pconst 1)    => AddInc y
  | Pcast _ (Pconst (-1)), y | y, Pcast _ (Pconst (-1)) => AddDec y
  | _, _ => AddNone
  end.

Variant sub_inc_dec : Type :=
  | SubInc
  | SubDec
  | SubNone.

Definition sub_inc_dec_classify (e: pexpr) :=
  match e with
  | Pcast _ (Pconst (-1)) => SubInc
  | Pcast _ (Pconst 1)    => SubDec
  | _                     => SubNone
  end.

Variant lower_cassgn_t : Type :=
  | LowerMov   of wsize 
  | LowerCopn  of sopn & pexpr
  | LowerInc   of sopn & pexpr
  | LowerFopn  of sopn & list pexpr
  | LowerEq    of wsize & pexpr & pexpr
  | LowerLt    of wsize & pexpr & pexpr
  | LowerIf    of         pexpr & pexpr & pexpr
  | LowerAssgn.

Definition wsize_of_lval x := 
  match x with
  | Lmem ws _ _ => ws
  | _           => U64
  end.

Definition lower_cassgn_classify e x : lower_cassgn_t :=
  match e with
  | Pcast _ (Pconst _)  
  | Pvar {| v_var := {| vtype := sword |} |}
  | Pget _ _ => LowerMov (wsize_of_lval x)

  | Pload ws _ _ => 
    if (wsize_of_lval x) == ws then LowerMov ws
    else LowerAssgn

  | Papp1 (Olnot ws) a => LowerCopn (Ox86_NOT ws) a
  | Papp1 (Oneg ws)  a => LowerFopn (Ox86_NEG ws) [:: a]

  | Papp2 op a b =>
    match op with
    | Oadd (Op_w ws) =>
      match add_inc_dec_classify a b with
      | AddInc y => LowerInc  (Ox86_INC ws) y
      | AddDec y => LowerInc  (Ox86_DEC ws) y
      | AddNone  => LowerFopn (Ox86_ADD ws) [:: a ; b ] (* TODO: lea *)
      end
    | Osub (Op_w ws) =>
      match sub_inc_dec_classify b with
      | SubInc  => LowerInc  (Ox86_INC ws) a
      | SubDec  => LowerInc  (Ox86_DEC ws) a
      | SubNone => LowerFopn (Ox86_SUB ws) [:: a ; b ]
      end
    | Omul (Op_w ws) => LowerFopn (Ox86_IMUL64 ws) [:: a ; b ]
    | Oland ws       => LowerFopn (Ox86_AND    ws) [:: a ; b ]
    | Olor  ws       => LowerFopn (Ox86_OR     ws) [:: a ; b ]
    | Olxor ws       => LowerFopn (Ox86_XOR    ws) [:: a ; b ]
    | Olsr  ws       => LowerFopn (Ox86_SHR    ws) [:: a ; b ]
    | Olsl  ws       => LowerFopn (Ox86_SHL    ws) [:: a ; b ]
    | Oasr  ws       => LowerFopn (Ox86_SAR    ws) [:: a ; b ]
    | Oeq (Cmp_sw ws | Cmp_uw ws ) => LowerEq ws a b
    | Olt (Cmp_uw ws) => LowerLt ws a b
    | _ => LowerAssgn
    end

  | Pif e e1 e2 => 
    if (stype_of_lval x == sword) then
      LowerIf e e1 e2
    else
      LowerAssgn
  | _ => LowerAssgn
  end.

Definition lower_cassgn (x: lval) (tg: assgn_tag) (e: pexpr) : seq instr_r :=
  let vi := var_info_of_lval x in
  let f := Lnone vi sbool in
  let copn o a := [:: Copn [:: x ] o [:: a] ] in
  let fopn o a := [:: Copn [:: f ; f ; f ; f ; f ; x ] o a ] in
  let inc o a := [:: Copn [:: f ; f ; f ; f ; x ] o [:: a ] ] in
  match lower_cassgn_classify e x with
  | LowerMov ws => copn (Ox86_MOV ws) e
  | LowerCopn o e => copn o e
  | LowerInc o e => inc o e
  | LowerFopn o es => fopn o es
  | LowerEq ws a b => [:: Copn [:: f ; f ; f ; f ; x ] (Ox86_CMP ws) [:: a ; b ] ]
  | LowerLt ws a b => [:: Copn [:: f ; x ; f ; f ; f ] (Ox86_CMP ws) [:: a ; b ] ]
  | LowerIf e e1 e2 =>
     let (l, e) := lower_condition vi e in
     l ++ [:: Copn [:: x] (Ox86_CMOVcc U64) [:: e; e1; e2]]
  | LowerAssgn => [:: Cassgn x tg e]
  end.

(* Lowering of Oaddcarry
… = #addc(x, y, false) → ADD(x, y)
… = #addc(?, ?, true) → #error
… = #addc(?, ?, c) → ADC
*)

Definition Lnone_b vi := Lnone vi sbool.

Definition lower_addcarry_classify ws (sub: bool) (xs: lvals) (es: pexprs) :=
  match xs, es with
  | [:: cf ; r ], [:: x ; y ; Pbool false ] =>
    let vi := var_info_of_lval r in
    Some (vi, if sub then Ox86_SUB ws else Ox86_ADD ws, [:: x ; y ], cf, r)
  | [:: cf ; r ], [:: _ ; _ ; Pvar cfi ] =>
    let vi := v_info cfi in
    Some (vi, (if sub then Ox86_SBB ws else Ox86_ADC ws), es, cf, r)
  | _, _ => None
  end.

Definition lower_addcarry ws (sub: bool) (xs: lvals) (es: pexprs) : seq instr_r :=
  match lower_addcarry_classify ws sub xs es with
  | Some (vi, o, es, cf, r) =>
    [:: Copn [:: Lnone_b vi; cf ; Lnone_b vi ; Lnone_b vi ; Lnone_b vi ; r ] o es ]
  | None => [:: Copn xs (if sub then Osubcarry ws else Oaddcarry ws) es ]
  end.

Definition lower_mulu ws (xs: lvals) (es: pexprs) : seq instr_r :=
  match xs, es with
  | [:: r1; r2 ], [:: x ; y ] =>
    let vi := var_info_of_lval r2 in
    let f := Lnone_b vi in
    match is_wconst x with
    | Some (ws', _) =>
      let c := {| v_var := {| vtype := sword; vname := fresh_multiplicand fv |} ; v_info := vi |} in
      [:: Copn [:: Lvar c ] (Ox86_MOV ws') [:: x ] ; Copn [:: f ; f ; f ; f ; f ; r1 ; r2 ] (Ox86_MUL ws) [:: y ; Pvar c ] ]
    | None =>
    match is_wconst y with
    | Some (ws', _) =>
      let c := {| v_var := {| vtype := sword; vname := fresh_multiplicand fv |} ; v_info := vi |} in
      [:: Copn [:: Lvar c ] (Ox86_MOV ws') [:: y ] ; Copn [:: f ; f ; f ; f ; f ; r1 ; r2 ] (Ox86_MUL ws) [:: x ; Pvar c ] ]
    | None => [:: Copn [:: f ; f ; f ; f ; f ; r1 ; r2 ] (Ox86_MUL ws) es ]
    end end
  | _, _ => [:: Copn xs (Omulu ws) es ]
  end.

Definition lower_copn (xs: lvals) (op: sopn) (es: pexprs) : seq instr_r :=
  match op with
  | Oaddcarry ws => lower_addcarry ws false xs es
  | Osubcarry ws => lower_addcarry ws true xs es
  | Omulu     ws => lower_mulu     ws xs es
  | _ => [:: Copn xs op es]
  end.

Definition lower_cmd (lower_i: instr -> cmd) (c:cmd) : cmd :=
  List.fold_right (fun i c' => lower_i i ++ c') [::] c.

Fixpoint lower_i (i:instr) : cmd :=
  let (ii, ir) := i in
  map (MkI ii)
  match ir with
  | Cassgn l t e => lower_cassgn l t e
  | Copn   l o e => lower_copn l o e
  | Cif e c1 c2  =>
     let '(pre, e) := lower_condition xH e in
     rcons pre (Cif e (lower_cmd lower_i c1) (lower_cmd lower_i c2))
  | Cfor v (d, lo, hi) c =>
     [:: Cfor v (d, lo, hi) (lower_cmd lower_i c)]
  | Cwhile c e c' =>
     let '(pre, e) := lower_condition xH e in
     [:: Cwhile ((lower_cmd lower_i c) ++ map (MkI xH) pre) e (lower_cmd lower_i c')]
  | _ => [:: ir]
  end.

Definition lower_fd (fd: fundef) : fundef :=
  {| f_iinfo := f_iinfo fd;
     f_params := f_params fd;
     f_body := lower_cmd lower_i (f_body fd);
     f_res := f_res fd
  |}.

Definition lower_prog (p: prog) := map_prog lower_fd p.

End LOWERING.
