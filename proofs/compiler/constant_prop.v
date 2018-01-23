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

(* ** Imports and settings *)
Require Import expr ZArith sem.
Import all_ssreflect all_algebra.
Import Utf8.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Local Open Scope seq_scope.
Local Open Scope vmap_scope.
Local Open Scope Z_scope.
(* -------------------------------------------------------------------------- *)
(* ** Smart constructors                                                      *)
(* -------------------------------------------------------------------------- *)

Definition szeroext_aux (e: pexpr) :=
  match e with
  | Pcast sz e' => Some (sz, λ sz, Pcast sz e')

  | Papp1 (Ozeroext sz) e' => Some (sz, λ sz, Papp1 (Ozeroext sz) e')
  | Papp1 (Olnot sz) e' => Some (sz, λ sz, Papp1 (Olnot sz) e')
  | Papp1 (Oneg (Op_w sz)) e' => Some (sz, λ sz, Papp1 (Oneg (Op_w sz)) e')

  | Papp2 (Oadd (Op_w sz)) e1 e2 => Some (sz, λ sz, Papp2 (Oadd (Op_w sz)) e1 e2)
  | Papp2 (Osub (Op_w sz)) e1 e2 => Some (sz, λ sz, Papp2 (Osub (Op_w sz)) e1 e2)
  | Papp2 (Omul (Op_w sz)) e1 e2 => Some (sz, λ sz, Papp2 (Omul (Op_w sz)) e1 e2)

  | Papp2 (Oland sz) e1 e2 => Some (sz, λ sz, Papp2 (Oland sz) e1 e2)
  | Papp2 (Olor sz) e1 e2 => Some (sz, λ sz, Papp2 (Olor sz) e1 e2)
  | Papp2 (Olxor sz) e1 e2 => Some (sz, λ sz, Papp2 (Olxor sz) e1 e2)
  | Papp2 (Olsr sz) e1 e2 => Some (sz, λ sz, Papp2 (Olsr sz) e1 e2)
  | Papp2 (Olsl sz) e1 e2 => Some (sz, λ sz, Papp2 (Olsl sz) e1 e2)
  | Papp2 (Oasr sz) e1 e2 => Some (sz, λ sz, Papp2 (Oasr sz) e1 e2)

  | _ => None end.

(* TODO: move to utils *)
(* TODO: move to stdlib *)
Scheme Equality for comparison.

Lemma comparison_eq_axiom : Equality.axiom comparison_beq.
Proof.
  move=> x y;apply:(iffP idP).
  + by apply: internal_comparison_dec_bl.
  by apply: internal_comparison_dec_lb.
Qed.

Definition comparison_eqMixin     := Equality.Mixin comparison_eq_axiom.
Canonical  comparison_eqType      := Eval hnf in EqType _ comparison_eqMixin.

Definition szeroext sz (e: pexpr) :=
  let default := Papp1 (Ozeroext sz) e in
  match szeroext_aux e with
  | Some (sz', k) =>
    (* if sz <= sz' one cast to sz is enough. *)
    if wsize_cmp sz' sz == Lt then default else k sz
  | None => default
  end.

Definition snot_bool (e:pexpr) := 
  match e with
  | Pbool b      => negb b
  | Papp1 Onot e => e 
  | _            => Papp1 Onot e
  end.

Definition snot_w (sz: wsize) (e:pexpr) :=
  match is_wconst sz e with
  | Some n => wconst (wnot n)
  | None   => Papp1 (Olnot sz) e
  end.

Definition sneg_int (e: pexpr) :=
  match e with
  | Pconst z => Pconst (- z)
  | Papp1 (Oneg Op_int) e' => e'
  | _ => Papp1 (Oneg Op_int) e
  end.

Definition sneg_w (sz: wsize) (e:pexpr) :=
  match is_wconst sz e with
  | Some n => wconst (- n)%R
  | None   => Papp1 (Oneg (Op_w sz)) e
  end.

Definition s_op1 o e :=
  match o with
  | Ozeroext sz => szeroext sz e
  | Onot  => snot_bool e 
  | Olnot sz => snot_w sz e
  | Oneg Op_int => sneg_int e
  | Oneg (Op_w sz) => sneg_w sz e
  | Oarr_init sz => Papp1 (Oarr_init sz) e
  end.

(* ------------------------------------------------------------------------ *)
Definition sand e1 e2 := 
  match is_bool e1, is_bool e2 with
  | Some b, _ => if b then e2 else false
  | _, Some b => if b then e1 else false
  | _, _      => Papp2 Oand e1 e2
  end.

Definition sor e1 e2 := 
   match is_bool e1, is_bool e2 with
  | Some b, _ => if b then Pbool true else e2
  | _, Some b => if b then Pbool true else e1
  | _, _       => Papp2 Oor e1 e2 
  end.

(* ------------------------------------------------------------------------ *)

Definition sadd_int e1 e2 := 
  match is_const e1, is_const e2 with
  | Some n1, Some n2 => Pconst (n1 + n2)
  | Some n, _ => 
    if (n == 0)%Z then e2 else Papp2 (Oadd Op_int) e1 e2
  | _, Some n => 
    if (n == 0)%Z then e1 else Papp2 (Oadd Op_int) e1 e2
  | _, _ => Papp2 (Oadd Op_int) e1 e2
  end.

Definition sadd_w sz e1 e2 :=
  match is_wconst sz e1, is_wconst sz e2 with
  | Some n1, Some n2 => wconst (n1 + n2)
  | Some n, _ => if n == 0%R then szeroext sz e2 else Papp2 (Oadd (Op_w sz)) e1 e2
  | _, Some n => if n == 0%R then szeroext sz e1 else Papp2 (Oadd (Op_w sz)) e1 e2
  | _, _ => Papp2 (Oadd (Op_w sz)) e1 e2
  end.

Definition sadd ty :=
  match ty with
  | Op_int => sadd_int
  | Op_w sz => sadd_w sz
  end.

Definition ssub_int e1 e2 := 
  match is_const e1, is_const e2 with
  | Some n1, Some n2 => Pconst (n1 - n2)
  | _, Some n => 
    if (n == 0)%Z then e1 else Papp2 (Osub Op_int) e1 e2
  | _, _ => Papp2 (Osub Op_int) e1 e2
  end.

Definition ssub_w sz e1 e2 :=
  match is_wconst sz e1, is_wconst sz e2 with
  | Some n1, Some n2 => wconst (n1 - n2)
  | _, Some n => if n == 0%R then szeroext sz e1 else Papp2 (Osub (Op_w sz)) e1 e2
  | _, _ => Papp2 (Osub (Op_w sz)) e1 e2
  end.

Definition ssub ty := 
  match ty with
  | Op_int => ssub_int
  | Op_w sz => ssub_w sz
  end.

Definition smul_int e1 e2 := 
  match is_const e1, is_const e2 with
  | Some n1, Some n2 => Pconst (n1 * n2)
  | Some n, _ => 
    if (n == 0)%Z then Pconst 0
    else if (n == 1)%Z then e2 
    else Papp2 (Omul Op_int) e1 e2
  | _, Some n => 
    if (n == 0)%Z then Pconst 0
    else if (n == 1)%Z then e1
    else Papp2 (Omul Op_int) e1 e2
  | _, _ => Papp2 (Omul Op_int) e1 e2
  end.

Definition smul_w sz e1 e2 :=
  match is_wconst sz e1, is_wconst sz e2 with
  | Some n1, Some n2 => wconst (n1 * n2)
  | Some n, _ =>
    if n == 0%R then @wconst sz 0
    else if n == 1%R then szeroext sz e2
    else Papp2 (Omul (Op_w sz)) (wconst n) e2
  | _, Some n => 
    if n == 0%R then @wconst sz 0
    else if n == 1%R then szeroext sz e1
    else Papp2 (Omul (Op_w sz)) e1 (wconst n)
  | _, _ => Papp2 (Omul (Op_w sz)) e1 e2
  end.

Definition smul ty := 
  match ty with
  | Op_int => smul_int
  | Op_w sz => smul_w sz
  end.

Definition s_eq ty e1 e2 := 
  if eq_expr e1 e2 then Pbool true 
  else 
    match ty with
    | Op_int =>
      match is_const e1, is_const e2 with
      | Some i1, Some i2 => Pbool (i1 == i2)
      | _, _             => Papp2 (Oeq ty) e1 e2
      end 
    | Op_w sz =>
      match is_wconst sz e1, is_wconst sz e2 with
      | Some i1, Some i2 => Pbool (i1 == i2)
      | _, _             => Papp2 (Oeq ty) e1 e2
      end
    end.

Definition sneq ty e1 e2 := 
  match is_bool (s_eq ty e1 e2) with
  | Some b => Pbool (~~ b)
  | None      => Papp2 (Oneq ty) e1 e2
  end.

Definition slt ty e1 e2 := 
  if eq_expr e1 e2 then Pbool false 
  else match is_const e1, is_const e2 with
  | Some n1, Some n2 => Pbool (n1 <? n2)%Z
  | _      , _       => Papp2 (Olt ty) e1 e2 
  end.

Definition sle ty e1 e2 := 
  if eq_expr e1 e2 then Pbool true 
  else match is_const e1, is_const e2 with
  | Some n1, Some n2 => Pbool (n1 <=? n2)%Z
  | _      , _       => Papp2 (Ole ty) e1 e2 
  end.

Definition sgt ty e1 e2 := 
  if eq_expr e1 e2 then Pbool false 
  else match is_const e1, is_const e2 with
  | Some n1, Some n2 => Pbool (n1 >? n2)%Z
  | _      , _       => Papp2 (Ogt ty) e1 e2 
  end.

Definition sge ty e1 e2 := 
  if eq_expr e1 e2 then Pbool true 
  else match is_const e1, is_const e2 with
  | Some n1, Some n2 => Pbool (n1 >=? n2)%Z
  | _      , _       => Papp2 (Oge ty) e1 e2 
  end.

Definition sbitw i (z: ∀ sz, word sz → word sz → word sz) sz e1 e2 :=
  match is_wconst sz e1, is_wconst sz e2 with
  | Some n1, Some n2 => wconst (z sz n1 n2)
  | _, _ => Papp2 (i sz) e1 e2
  end.

(* TODO: could be improved when one operand is known *)
Definition sland := sbitw Oland (@wand).
Definition slor := sbitw Olor (@wor).
Definition slxor := sbitw Olxor (@wxor).

Definition sbitw8 i (z: ∀ sz, word sz → u8 → word sz) sz e1 e2 :=
  match is_wconst sz e1, is_wconst U8 e2 with
  | Some n1, Some n2 => wconst (z sz n1 n2)
  | _, _ => Papp2 (i sz) e1 e2
  end.

Definition sshr sz e1 e2 :=
  sbitw8 Olsr (@sem_shr) sz e1 e2.

Definition sshl sz e1 e2 :=
   sbitw8 Olsl (@sem_shl) sz e1 e2.

Definition ssar sz e1 e2 :=
  sbitw8 Oasr (@sem_sar) sz e1 e2.

Definition s_op2 o e1 e2 := 
  match o with 
  | Oand    => sand e1 e2 
  | Oor     => sor  e1 e2
  | Oadd ty => sadd ty e1 e2
  | Osub ty => ssub ty e1 e2
  | Omul ty => smul ty e1 e2
  | Oeq  ty => s_eq ty e1 e2
  | Oneq ty => sneq ty e1 e2
  | Olt  ty => slt  ty e1 e2
  | Ole  ty => sle  ty e1 e2
  | Ogt  ty => sgt  ty e1 e2
  | Oge  ty => sge  ty e1 e2
  | Oland sz => sland sz e1 e2
  | Olor sz => slor sz e1 e2
  | Olxor sz => slxor sz e1 e2
  | Olsr sz => sshr sz e1 e2
  | Olsl sz => sshl sz e1 e2
  | Oasr sz => ssar sz e1 e2
  end.

Definition s_if e e1 e2 := 
  match is_bool e with
  | Some b => if b then e1 else e2
  | None   => Pif e e1 e2
  end.

(* ** constant propagation 
 * -------------------------------------------------------------------- *)

Variant const_v :=
  | Cint of Z
  | Cword sz `(word sz).

Definition const_v_beq (c1 c2: const_v) : bool :=
  match c1, c2 with
  | Cint z1, Cint z2 => z1 == z2
  | Cword sz1 w1, Cword sz2 w2 =>
    match wsize_eq_dec sz1 sz2 with
    | left e => eq_rect _ word w1 _ e == w2
    | _ => false
    end
  | _, _ => false
  end.

Lemma const_v_eq_axiom : Equality.axiom const_v_beq.
Proof.
case => [ z1 | sz1 w1 ] [ z2 | sz2 w2] /=; try (constructor; congruence).
+ case: eqP => [ -> | ne ]; constructor; congruence.
case: wsize_eq_dec => [ ? | ne ]; last (constructor; congruence).
subst => /=.
by apply:(iffP idP) => [ /eqP | [] ] ->.
Qed.

Definition const_v_eqMixin     := Equality.Mixin const_v_eq_axiom.
Canonical  const_v_eqType      := Eval hnf in EqType const_v const_v_eqMixin.

Local Notation cpm := (Mvar.t const_v).

Definition const v := 
  match v with
  | Cint z  => Pconst z
  | Cword sz z => wconst z
  end.

Fixpoint const_prop_e (m:cpm) e :=
  match e with
  | Pconst _      => e
  | Pbool  _      => e
  | Pcast sz e       => Pcast sz (const_prop_e m e)
  | Pvar  x       => if Mvar.get m x is Some n then const n else e
  | Pglobal _ => e
  | Pget  x e     => Pget x (const_prop_e m e)
  | Pload sz x e     => Pload sz x (const_prop_e m e)
  | Papp1 o e     => s_op1 o (const_prop_e m e)
  | Papp2 o e1 e2 => s_op2 o (const_prop_e m e1)  (const_prop_e m e2)
  | Pif e e1 e2   => s_if (const_prop_e m e) (const_prop_e m e1) (const_prop_e m e2)
  end.

Definition empty_cpm : cpm := @Mvar.empty const_v.

Definition merge_cpm : cpm -> cpm -> cpm := 
  Mvar.map2 (fun _ (o1 o2: option const_v) => 
   match o1, o2 with
   | Some n1, Some n2 => 
     if (n1 == n2)%Z then Some n1
     else None
   | _, _ => None
   end).

Definition remove_cpm (m:cpm) (s:Sv.t): cpm :=
  Sv.fold (fun x m => Mvar.remove m x) s m.

Definition const_prop_rv (m:cpm) (rv:lval) : cpm * lval := 
  match rv with 
  | Lnone _ _ => (m, rv)
  | Lvar  x   => (Mvar.remove m x, rv)
  | Lmem sz x e => (m, Lmem sz x (const_prop_e m e))
  | Laset x e => (Mvar.remove m x, Laset x (const_prop_e m e))
  end.

Fixpoint const_prop_rvs (m:cpm) (rvs:lvals) : cpm * lvals := 
  match rvs with
  | [::] => (m, [::])
  | rv::rvs => 
    let (m,rv)  := const_prop_rv m rv in 
    let (m,rvs) := const_prop_rvs m rvs in
    (m, rv::rvs)
  end.

Definition wsize_of_stype (ty: stype) : wsize :=
  if ty is sword sz then sz else U64.

Definition add_cpm (m:cpm) (rv:lval) tag e := 
  if rv is Lvar x then
    if tag is AT_inline then 
      match e with
      | Pconst z =>  Mvar.set m x (Cint z)
      | Pcast sz' (Pconst z) =>
        let sz := wsize_of_stype (vtype x) in
        Mvar.set m x (Cword (zero_extend sz (wrepr sz' z)))
      | _ => m
      end
    else m
  else m.
                           
Section CMD.

  Variable const_prop_i : cpm -> instr -> cpm * cmd.

  Fixpoint const_prop (m:cpm) (c:cmd) : cpm * cmd :=
    match c with
    | [::] => (m, [::])
    | i::c =>
      let (m,ic) := const_prop_i m i in
      let (m, c) := const_prop m c in
      (m, ic ++ c)
    end.

End CMD.

Fixpoint const_prop_ir (m:cpm) ii (ir:instr_r) : cpm * cmd := 
  match ir with
  | Cassgn x tag e => 
    let e := const_prop_e m e in 
    let (m,x) := const_prop_rv m x in
    let m := add_cpm m x tag e in
    (m, [:: MkI ii (Cassgn x tag e)])

  | Copn xs t o es =>
    (* TODO: Improve this *)
    let es := map (const_prop_e m) es in
    let (m,xs) := const_prop_rvs m xs in
    (m, [:: MkI ii (Copn xs t o es) ])

  | Cif b c1 c2 => 
    let b := const_prop_e m b in
    match is_bool b with
    | Some b => 
      let c := if b then c1 else c2 in 
      const_prop const_prop_i m c
    | None =>
      let (m1,c1) := const_prop const_prop_i m c1 in
      let (m2,c2) := const_prop const_prop_i m c2 in
      (merge_cpm m1 m2, [:: MkI ii (Cif b c1 c2) ])
    end

  | Cfor x (dir, e1, e2) c =>
    let e1 := const_prop_e m e1 in
    let e2 := const_prop_e m e2 in
    let m := remove_cpm m (write_i ir) in
    let (_,c) := const_prop const_prop_i m c in
    (m, [:: MkI ii (Cfor x (dir, e1, e2) c) ])

  | Cwhile c e c' =>
    let m := remove_cpm m (write_i ir) in
    let (m',c) := const_prop const_prop_i m c in
    let e := const_prop_e m' e in
    let (_,c') := const_prop const_prop_i m' c' in
    let cw := 
      match is_bool e with
      | Some false => c
      | _          => [:: MkI ii (Cwhile c e c')]
      end in
    (m', cw)
  | Ccall fi xs f es =>
    let es := map (const_prop_e m) es in
    let (m,xs) := const_prop_rvs m xs in
    (m, [:: MkI ii (Ccall fi xs f es) ])
  end

with const_prop_i (m:cpm) (i:instr) : cpm * cmd :=
  let (ii,ir) := i in
  const_prop_ir m ii ir.

Definition const_prop_fun (f:fundef) :=
  let (ii,p,c,r) := f in
  let (_, c) := const_prop const_prop_i empty_cpm c in
  MkFun ii p c r.

Definition const_prop_prog (p:prog) : prog := map_prog const_prop_fun p.

