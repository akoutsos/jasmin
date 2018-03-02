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

(* * Syntax and semantics of the dmasm source language *)

(* ** Imports and settings *)
From mathcomp Require Import all_ssreflect all_algebra.
Require Import Psatz xseq.
Require Export expr low_memory sem.
Import Utf8.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Local Open Scope Z_scope.

(* ** Interpretation of types
 * -------------------------------------------------------------------- *)

Record pword s := 
  { pw_size: wsize; pw_word : word pw_size; pw_proof : (pw_size <= s)%CMP }.

Definition psem_t (t : stype) : Type :=
  match t with
  | sbool    => bool
  | sint     => Z
  | sarr s n => Array.array n (word s)
  | sword s  => pword s
  end.


(* ** Default values
 * -------------------------------------------------------------------- *)

Definition pword_of_word (s:wsize) (w:word s) : pword s :=
  {|pw_word := w; pw_proof := cmp_le_refl s|}.

Definition to_pword (s: wsize) (v: value) : exec (pword s) :=
   match v with
   | Vword s' w =>
     if Sumbool.sumbool_of_bool (s' ≤ s)%CMP is left heq
     then ok {| pw_word := w ; pw_proof := heq |}
     else truncate_word s w >>= λ w, ok (pword_of_word w)
   | Vundef (sword _) => undef_error
   | _                => type_error
   end.

Lemma sumbool_of_boolET (b: bool) (h: b) :
  Sumbool.sumbool_of_bool b = left h.
Proof. by move: h; rewrite /is_true => ?; subst. Qed.

Lemma sumbool_of_boolEF (b: bool) (h: b = false) :
  Sumbool.sumbool_of_bool b = right h.
Proof. by move: h; rewrite /is_true => ?; subst. Qed.

Definition pof_val t : value -> exec (psem_t t) :=
  match t return value -> exec (psem_t t) with
  | sbool    => to_bool
  | sint     => to_int
  | sarr s n => to_arr s n
  | sword s  => to_pword s
  end.

Definition pto_val t : psem_t t -> value :=
  match t return psem_t t -> value with
  | sbool    => Vbool
  | sint     => Vint
  | sarr s n => @Varr s n 
  | sword s  => fun w => Vword (pw_word w)
  end.

(* ** Variable map
 * -------------------------------------------------------------------- *)

Notation vmap     := (Fv.t (fun t => exec (psem_t t))).

Definition pundef_addr t := 
  match t return exec (psem_t t) with
  | sbool | sint | sword _ => undef_error
  | sarr s n => ok (@Array.empty _ n)
  end.

Definition vmap0 : vmap :=
  @Fv.empty (fun t => exec (psem_t t)) (fun x => pundef_addr x.(vtype)).

Definition get_var (m:vmap) x :=
  on_vu (@pto_val (vtype x)) (ok (Vundef (vtype x))) (m.[x]%vmap).

(* We do not allows to assign to a variable of type word an undef value *)
Definition set_var (m:vmap) x v : exec vmap :=
  on_vu (fun v => m.[x<-ok v]%vmap)
        (if is_sword x.(vtype) then type_error
         else ok m.[x<-pundef_addr x.(vtype)]%vmap)
        (pof_val (vtype x) v).

Definition is_full_array v :=
  match v with
  | Vundef _ => False
  | Varr s n t =>
    forall p, (0 <= p < Zpos n)%Z -> exists w, Array.get t p = ok w
  | _ => True
  end.

(* ** Parameter expressions
 * -------------------------------------------------------------------- *)

Import Memory.

Record estate := Estate {
  emem : mem;
  evm  : vmap
}.

Definition on_arr_var A (s:estate) (x:var) (f:forall sz n, Array.array n (word sz)-> exec A) :=
  Let v := get_var s.(evm) x in
  match v with
  | Varr sz n t => f sz n t
  | _ => type_error
  end.

Notation "'Let' ( sz , n , t ) ':=' s '.[' x ']' 'in' body" :=
  (@on_arr_var _ s x (fun sz n (t:Array.array n (word sz)) => body)) 
  (at level 25, s at level 0).
  
Section SEM_PEXPR.

Context (gd: glob_defs).

Fixpoint sem_pexpr (s:estate) (e : pexpr) : exec value :=
  match e with
  | Pconst z => ok (Vint z)
  | Pbool b  => ok (Vbool b)
  | Pcast sz e  =>
    Let z := sem_pexpr s e >>= to_int in
    ok (Vword (wrepr sz z))
  | Pvar v => get_var s.(evm) v
  | Pglobal g => get_global gd g
  | Pget x e =>
      Let (sz, n, t) := s.[x] in
      Let i := sem_pexpr s e >>= to_int in
      Let w := Array.get t i in
      ok (Vword w)
  | Pload sz x e =>
    Let w1 := get_var s.(evm) x >>= to_pointer in
    Let w2 := sem_pexpr s e >>= to_pointer in
    Let w  := read_mem s.(emem) (w1 + w2) sz in
    ok (@to_val (sword sz) w)
  | Papp1 o e1 =>
    Let v1 := sem_pexpr s e1 in
    sem_sop1 o v1
  | Papp2 o e1 e2 =>
    Let v1 := sem_pexpr s e1 in
    Let v2 := sem_pexpr s e2 in
    sem_sop2 o v1 v2
  | Pif e e1 e2 =>
    Let b := sem_pexpr s e >>= to_bool in
    Let v1 := sem_pexpr s e1 in
    Let v2 := sem_pexpr s e2 in
    if vundef_type (type_of_val v1) == vundef_type (type_of_val v2) then
      ok (if b then v1 else v2)
    else type_error
  end.

Definition sem_pexprs s := mapM (sem_pexpr s).

Definition write_var (x:var_i) (v:value) (s:estate) : exec estate :=
  Let vm := set_var s.(evm) x v in
  ok ({| emem := s.(emem); evm := vm |}).

Definition write_vars xs vs s :=
  fold2 ErrType write_var xs vs s.

Definition write_none (s:estate) ty v :=
  on_vu (fun v => s) (if is_sword ty then type_error else ok s)
          (pof_val ty v).

Definition write_lval (l:lval) (v:value) (s:estate) : exec estate :=
  match l with
  | Lnone _ ty => write_none s ty v
  | Lvar x => write_var x v s
  | Lmem sz x e =>
    Let vx := get_var (evm s) x >>= to_pointer in
    Let ve := sem_pexpr s e >>= to_pointer in
    let p := (vx + ve)%R in (* should we add the size of value, i.e vx + sz * se *)
    Let w := to_word sz v in
    Let m :=  write_mem s.(emem) p sz w in
    ok {| emem := m;  evm := s.(evm) |}
  | Laset x i =>
    Let (sz,n,t) := s.[x] in
    Let i := sem_pexpr s i >>= to_int in
    Let v := to_word sz v in
    Let t := Array.set t i v in
    Let vm := set_var s.(evm) x (@to_val (sarr sz n) t) in
    ok ({| emem := s.(emem); evm := vm |})
  end.

Definition write_lvals (s:estate) xs vs :=
   fold2 ErrType write_lval xs vs s.

End SEM_PEXPR.

(* ** Instructions
 * -------------------------------------------------------------------- *)

Section SEM.

Variable P:prog.
Context (gd: glob_defs).

Definition sem_range (s : estate) (r : range) :=
  let: (d,pe1,pe2) := r in
  Let i1 := sem_pexpr gd s pe1 >>= to_int in
  Let i2 := sem_pexpr gd s pe2 >>= to_int in
  ok (wrange d i1 i2).

Definition sem_sopn o m lvs args :=
  sem_pexprs gd m args >>= exec_sopn o >>= write_lvals gd m lvs.

Inductive sem : estate -> cmd -> estate -> Prop :=
| Eskip s :
    sem s [::] s

| Eseq s1 s2 s3 i c :
    sem_I s1 i s2 -> sem s2 c s3 -> sem s1 (i::c) s3

with sem_I : estate -> instr -> estate -> Prop :=
| EmkI ii i s1 s2:
    sem_i s1 i s2 ->
    sem_I s1 (MkI ii i) s2

with sem_i : estate -> instr_r -> estate -> Prop :=
| Eassgn s1 s2 (x:lval) tag ty e v:
    sem_pexpr gd s1 e = ok v ->
    check_ty_val ty v ->
    write_lval gd x v s1 = ok s2 ->
    sem_i s1 (Cassgn x tag ty e) s2

| Eopn s1 s2 t o xs es:
    sem_sopn o s1 xs es = ok s2 ->
    sem_i s1 (Copn xs t o es) s2

| Eif_true s1 s2 e c1 c2 :
    sem_pexpr gd s1 e = ok (Vbool true) ->
    sem s1 c1 s2 ->
    sem_i s1 (Cif e c1 c2) s2

| Eif_false s1 s2 e c1 c2 :
    sem_pexpr gd s1 e = ok (Vbool false) ->
    sem s1 c2 s2 ->
    sem_i s1 (Cif e c1 c2) s2

| Ewhile_true s1 s2 s3 s4 c e c' :
    sem s1 c s2 ->
    sem_pexpr gd s2 e = ok (Vbool true) ->
    sem s2 c' s3 ->
    sem_i s3 (Cwhile c e c') s4 ->
    sem_i s1 (Cwhile c e c') s4

| Ewhile_false s1 s2 c e c' :
    sem s1 c s2 ->
    sem_pexpr gd s2 e = ok (Vbool false) ->
    sem_i s1 (Cwhile c e c') s2

| Efor s1 s2 (i:var_i) d lo hi c vlo vhi :
    sem_pexpr gd s1 lo = ok (Vint vlo) ->
    sem_pexpr gd s1 hi = ok (Vint vhi) ->
    sem_for i (wrange d vlo vhi) s1 c s2 ->
    sem_i s1 (Cfor i (d, lo, hi) c) s2

| Ecall s1 m2 s2 ii xs f args vargs vs :
    sem_pexprs gd s1 args = ok vargs ->
    sem_call s1.(emem) f vargs m2 vs ->
    write_lvals gd {|emem:= m2; evm := s1.(evm) |} xs vs = ok s2 ->
    sem_i s1 (Ccall ii xs f args) s2

with sem_for : var_i -> seq Z -> estate -> cmd -> estate -> Prop :=
| EForDone s i c :
    sem_for i [::] s c s

| EForOne s1 s1' s2 s3 i w ws c :
    write_var i (Vint w) s1 = ok s1' ->
    sem s1' c s2 ->
    sem_for i ws s2 c s3 ->
    sem_for i (w :: ws) s1 c s3

with sem_call : mem -> funname -> seq value -> mem -> seq value -> Prop :=
| EcallRun m1 m2 fn f vargs s1 vm2 vres:
    get_fundef P fn = Some f ->
    all2 check_ty_val f.(f_tyin) vargs ->
    write_vars f.(f_params) vargs (Estate m1 vmap0) = ok s1 ->
    sem s1 f.(f_body) (Estate m2 vm2) ->
    mapM (fun (x:var_i) => get_var vm2 x) f.(f_res) = ok vres ->
    all2 check_ty_val f.(f_tyout) vres ->
    sem_call m1 fn vargs m2 vres.

(* -------------------------------------------------------------------- *)
(* The generated scheme is borring to use *)
(*
Scheme sem_Ind    := Induction for sem      Sort Prop
with sem_i_Ind    := Induction for sem_i    Sort Prop
with sem_I_Ind    := Induction for sem_I    Sort Prop
with sem_for_Ind  := Induction for sem_for  Sort Prop
with sem_call_Ind := Induction for sem_call Sort Prop.
*)

Section SEM_IND.
  Variables
    (Pc   : estate -> cmd -> estate -> Prop)
    (Pi_r : estate -> instr_r -> estate -> Prop)
    (Pi : estate -> instr -> estate -> Prop)
    (Pfor : var_i -> seq Z -> estate -> cmd -> estate -> Prop)
    (Pfun : mem -> funname -> seq value -> mem -> seq value -> Prop).

  Hypothesis Hnil : forall s : estate, Pc s [::] s.

  Hypothesis Hcons : forall (s1 s2 s3 : estate) (i : instr) (c : cmd),
    sem_I s1 i s2 -> Pi s1 i s2 -> sem s2 c s3 -> Pc s2 c s3 -> Pc s1 (i :: c) s3.

  Hypothesis HmkI : forall (ii : instr_info) (i : instr_r) (s1 s2 : estate),
    sem_i s1 i s2 -> Pi_r s1 i s2 -> Pi s1 (MkI ii i) s2.

  Hypothesis Hasgn : forall (s1 s2 : estate) (x : lval) (tag : assgn_tag) ty (e : pexpr) v,
    sem_pexpr gd s1 e = ok v ->
    check_ty_val ty v ->
    write_lval gd x v s1 = ok s2 ->
    Pi_r s1 (Cassgn x tag ty e) s2.

  Hypothesis Hopn : forall (s1 s2 : estate) t (o : sopn) (xs : lvals) (es : pexprs),
    sem_sopn o s1 xs es = Ok error s2 ->
    Pi_r s1 (Copn xs t o es) s2.

  Hypothesis Hif_true : forall (s1 s2 : estate) (e : pexpr) (c1 c2 : cmd),
    sem_pexpr gd s1 e = ok (Vbool true) ->
    sem s1 c1 s2 -> Pc s1 c1 s2 -> Pi_r s1 (Cif e c1 c2) s2.

  Hypothesis Hif_false : forall (s1 s2 : estate) (e : pexpr) (c1 c2 : cmd),
    sem_pexpr gd s1 e = ok (Vbool false) ->
    sem s1 c2 s2 -> Pc s1 c2 s2 -> Pi_r s1 (Cif e c1 c2) s2.

  Hypothesis Hwhile_true : forall (s1 s2 s3 s4 : estate) (c : cmd) (e : pexpr) (c' : cmd),
    sem s1 c s2 -> Pc s1 c s2 ->
    sem_pexpr gd s2 e = ok (Vbool true) ->
    sem s2 c' s3 -> Pc s2 c' s3 ->
    sem_i s3 (Cwhile c e c') s4 -> Pi_r s3 (Cwhile c e c') s4 -> Pi_r s1 (Cwhile c e c') s4.

  Hypothesis Hwhile_false : forall (s1 s2 : estate) (c : cmd) (e : pexpr) (c' : cmd),
    sem s1 c s2 -> Pc s1 c s2 ->
    sem_pexpr gd s2 e = ok (Vbool false) ->
    Pi_r s1 (Cwhile c e c') s2.

  Hypothesis Hfor : forall (s1 s2 : estate) (i : var_i) (d : dir)
         (lo hi : pexpr) (c : cmd) (vlo vhi : Z),
    sem_pexpr gd s1 lo = ok (Vint vlo) ->
    sem_pexpr gd s1 hi = ok (Vint vhi) ->
    sem_for i (wrange d vlo vhi) s1 c s2 ->
    Pfor i (wrange d vlo vhi) s1 c s2 -> Pi_r s1 (Cfor i (d, lo, hi) c) s2.

  Hypothesis Hfor_nil : forall (s : estate) (i : var_i) (c : cmd), Pfor i [::] s c s.

  Hypothesis Hfor_cons : forall (s1 s1' s2 s3 : estate) (i : var_i)
         (w : Z) (ws : seq Z) (c : cmd),
    write_var i w s1 = Ok error s1' ->
    sem s1' c s2 -> Pc s1' c s2 ->
    sem_for i ws s2 c s3 -> Pfor i ws s2 c s3 -> Pfor i (w :: ws) s1 c s3.

  Hypothesis Hcall : forall (s1 : estate) (m2 : mem) (s2 : estate)
         (ii : inline_info) (xs : lvals)
         (fn : funname) (args : pexprs) (vargs vs : seq value),
    sem_pexprs gd s1 args = Ok error vargs ->
    sem_call (emem s1) fn vargs m2 vs -> Pfun (emem s1) fn vargs m2 vs ->
    write_lvals gd {| emem := m2; evm := evm s1 |} xs vs = Ok error s2 ->
    Pi_r s1 (Ccall ii xs fn args) s2.

  Hypothesis Hproc : forall (m1 m2 : mem) (fn:funname) (f : fundef) (vargs : seq value)
         (s1 : estate) (vm2 : vmap) (vres : seq value),
    get_fundef P fn = Some f ->
    all2 check_ty_val f.(f_tyin) vargs ->
    write_vars (f_params f) vargs {| emem := m1; evm := vmap0 |} = ok s1 ->
    sem s1 (f_body f) {| emem := m2; evm := vm2 |} ->
    Pc s1 (f_body f) {| emem := m2; evm := vm2 |} ->
    mapM (fun x : var_i => get_var vm2 x) (f_res f) = ok vres ->
    all2 check_ty_val f.(f_tyout) vres ->
    Pfun m1 fn vargs m2 vres.

  Fixpoint sem_Ind (e : estate) (l : cmd) (e0 : estate) (s : sem e l e0) {struct s} :
    Pc e l e0 :=
    match s in (sem e1 l0 e2) return (Pc e1 l0 e2) with
    | Eskip s0 => Hnil s0
    | @Eseq s1 s2 s3 i c s0 s4 =>
        @Hcons s1 s2 s3 i c s0 (@sem_I_Ind s1 i s2 s0) s4 (@sem_Ind s2 c s3 s4)
    end

  with sem_i_Ind (e : estate) (i : instr_r) (e0 : estate) (s : sem_i e i e0) {struct s} :
    Pi_r e i e0 :=
    match s in (sem_i e1 i0 e2) return (Pi_r e1 i0 e2) with
    | @Eassgn s1 s2 x tag ty e1 v h1 h2 h3 => @Hasgn s1 s2 x tag ty e1 v h1 h2 h3
    | @Eopn s1 s2 t o xs es e1 => @Hopn s1 s2 t o xs es e1
    | @Eif_true s1 s2 e1 c1 c2 e2 s0 =>
      @Hif_true s1 s2 e1 c1 c2 e2 s0 (@sem_Ind s1 c1 s2 s0)
    | @Eif_false s1 s2 e1 c1 c2 e2 s0 =>
      @Hif_false s1 s2 e1 c1 c2 e2 s0 (@sem_Ind s1 c2 s2 s0)
    | @Ewhile_true s1 s2 s3 s4 c e1 c' s0 e2 s5 s6 =>
      @Hwhile_true s1 s2 s3 s4 c e1 c' s0 (@sem_Ind s1 c s2 s0) e2 s5 (@sem_Ind s2 c' s3 s5) s6
          (@sem_i_Ind s3 (Cwhile c e1 c') s4 s6)
    | @Ewhile_false s1 s2 c e1 c' s0 e2 =>
      @Hwhile_false s1 s2 c e1 c' s0 (@sem_Ind s1 c s2 s0) e2
    | @Efor s1 s2 i0 d lo hi c vlo vhi e1 e2 s0 =>
      @Hfor s1 s2 i0 d lo hi c vlo vhi e1 e2 s0
        (@sem_for_Ind i0 (wrange d vlo vhi) s1 c s2 s0)
    | @Ecall s1 m2 s2 ii xs f13 args vargs vs e2 s0 e3 =>
      @Hcall s1 m2 s2 ii xs f13 args vargs vs e2 s0
        (@sem_call_Ind (emem s1) f13 vargs m2 vs s0) e3
    end

  with sem_I_Ind (e : estate) (i : instr) (e0 : estate) (s : sem_I e i e0) {struct s} :
    Pi e i e0 :=
    match s in (sem_I e1 i0 e2) return (Pi e1 i0 e2) with
    | @EmkI ii i0 s1 s2 s0 => @HmkI ii i0 s1 s2 s0 (@sem_i_Ind s1 i0 s2 s0)
    end

  with sem_for_Ind (v : var_i) (l : seq Z) (e : estate) (l0 : cmd) (e0 : estate)
         (s : sem_for v l e l0 e0) {struct s} : Pfor v l e l0 e0 :=
    match s in (sem_for v0 l1 e1 l2 e2) return (Pfor v0 l1 e1 l2 e2) with
    | EForDone s0 i c => Hfor_nil s0 i c
    | @EForOne s1 s1' s2 s3 i w ws c e1 s0 s4 =>
      @Hfor_cons s1 s1' s2 s3 i w ws c e1 s0 (@sem_Ind s1' c s2 s0)
         s4 (@sem_for_Ind i ws s2 c s3 s4)
    end

  with sem_call_Ind (m : mem) (f13 : funname) (l : seq value) (m0 : mem)
         (l0 : seq value) (s : sem_call m f13 l m0 l0) {struct s} : Pfun m f13 l m0 l0 :=
    match s with
    | @EcallRun m1 m2 fn f vargs s1 vm2 vres Hget Hca Hw Hsem Hvres Hcr =>
       @Hproc m1 m2 fn f vargs s1 vm2 vres Hget Hca Hw Hsem (sem_Ind Hsem) Hvres Hcr
    end.

End SEM_IND.

End SEM.

(* -------------------------------------------------------------------- *)
(* Proving some properties                                              *)
(* -------------------------------------------------------------------- *)

Lemma truncate_word_u s (a : word s): truncate_word s a = ok a.
Proof. by rewrite /truncate_word cmp_le_refl zero_extend_u. Qed.

Lemma truncate_wordP s1 s2 (w1:word s1) (w2:word s2) : 
  truncate_word s1 w2 = ok w1 → 
  (s1 <= s2)%CMP /\ w1 = zero_extend s1 w2.
Proof. by rewrite /truncate_word;case:ifP => // Hle []. Qed.

Lemma of_val_to_val vt (v: sem_t vt): of_val vt (to_val v) = ok v.
Proof.
  case: vt v=> // [s p | s] v /=;last by apply truncate_word_u.
  by rewrite /to_arr /= eq_dec_refl pos_dec_n_n /=.
Qed.

Lemma to_bool_inv x b :
  to_bool x = ok b →
  x = b.
Proof. case: x => // i' H. apply ok_inj in H. congruence. by case: i' H. Qed.

Lemma of_val_bool v b: of_val sbool v = ok b -> v = Vbool b.
Proof. by case v=> //= [? [->] | []]. Qed.

Lemma of_val_int v z: of_val sint v = ok z -> v = Vint z.
Proof. by case v=> //= [? [->] | []]. Qed.

Lemma of_val_word sz v w:
  of_val (sword sz) v = ok w ->
  ∃ sz' (w': word sz'), [/\ (sz <= sz')%CMP, v = Vword w' & w = zero_extend sz w'].
Proof.
 case: v => //=.
 + by move=> s w' /truncate_wordP [];exists s, w'.
 by case => // ?;case: ifP => //.
Qed.

Lemma to_arr_ok s n v t :
  to_arr s n v = ok t →
  v = @Varr s n t.
Proof.
case: v => // [ sz' n' a | [] // sz' n' ] /=; last by case: andP.
case: wsize_eq_dec => // ?; subst.
case: CEDecStype.pos_dec => // ?; subst.
by case => ->.
Qed.

Lemma on_vuP T R (fv: T -> R) (fu: exec R) (v:exec T) r P0:
  (forall t, v = ok t -> fv t = r -> P0) ->
  (v = Error ErrAddrUndef -> fu = ok r -> P0) ->
  on_vu fv fu v = ok r -> P0.
Proof. by case: v => [a | []] Hfv Hfu //=;[case; apply: Hfv | apply Hfu]. Qed.

Lemma set_varP (m m':vmap) x v P0 :
   (forall t, pof_val (vtype x) v = ok t -> m.[x <- ok t]%vmap = m' -> P0) ->
   ( ~~is_sword x.(vtype)  ->
     pof_val (vtype x) v = Error ErrAddrUndef ->
     m.[x<-pundef_addr x.(vtype)]%vmap = m' -> P0) ->
   set_var m x v = ok m' -> P0.
Proof.
  move=> H1 H2;apply on_vuP => //.
  by case:ifPn => // neq herr [];apply : H2.
Qed.

Definition apply_undef t (v : exec (psem_t t)) :=
  match v with
  | Error ErrAddrUndef => pundef_addr t
  | _                  => v
  end.

Lemma on_arr_varP A (f : forall sz n, Array.array n (word sz) -> exec A) v s x P0:
  (forall sz n t, vtype x = sarr sz n ->
               get_var (evm s) x = ok (@Varr sz n t) ->
               f sz n t = ok v -> P0) ->
  on_arr_var s x f = ok v -> P0.
Proof.
  rewrite /on_arr_var=> H;apply: rbindP => vx.
  case: x H => -[ | | sz n | sz ] nx;rewrite /get_var => H;
    case Heq : ((evm s).[_])%vmap => [v' | e] //=.
  + by move=> [<-]. + by case: (e) => // -[<-].
  + by move=> [<-]. + by case: (e) => // -[<-].
  + by move=> [<-]; apply: H => //;rewrite Heq. + by case: (e) => // -[<-].
  + by move=> [<-]. + by case: (e) => // -[<-].
Qed.

Definition Varr_inj sz sz' n n' t t' (e: @Varr sz n t = @Varr sz' n' t') :
  n = n' ∧
  ∃ e : sz = sz', eq_rect sz (λ s, Array.array n (word s)) t sz' e = t' :=
  let 'Logic.eq_refl := e in conj erefl (ex_intro _ erefl erefl).

Lemma Varr_inj1 sz n t t' : @Varr sz n t = @Varr sz n t' -> t = t'.
Proof.
  move => /Varr_inj [_] [] e.
  by rewrite (Eqdep_dec.UIP_dec wsize_eq_dec e erefl).
Qed.

Definition Vword_inj sz sz' w w' (e: @Vword sz w = @Vword sz' w') :
  ∃ e : sz = sz', eq_rect sz (λ s, (word s)) w sz' e = w' :=
  let 'Logic.eq_refl := e in (ex_intro _ erefl erefl).

Lemma is_wconstP gd s sz e w:
  is_wconst sz e = Some w →
  sem_pexpr gd s e >>= to_word sz = ok w.
Proof.
  case: e => // sz' e;rewrite /is_wconst;case:ifP => // hle /oseq.obindI [z] [h] [<-].
  have := is_constP e; rewrite h => {h} h; inversion h => {h}; subst.
  by rewrite /= /truncate_word hle. 
Qed.

Lemma sem_op1_b_dec gd v s e f:
  Let v1 := sem_pexpr gd s e in sem_op1_b f v1 = ok v ->
  exists z, Vbool (f z) = v /\ sem_pexpr gd s e = ok (Vbool z).
Proof.
  rewrite /sem_op1_b /mk_sem_sop1.
  t_xrbindP=> -[] //.
  + by move=> b -> b1 []<- <-; exists b; split.
  + by move=> [] //.
Qed.

Lemma sem_op2_b_dec gd v s e1 e2 f:
  Let v1 := sem_pexpr gd s e1 in (Let v2 := sem_pexpr gd s e2 in sem_op2_b f v1 v2) = ok v ->
  exists z1 z2, Vbool (f z1 z2) = v /\ sem_pexpr gd s e1 = ok (Vbool z1) /\ sem_pexpr gd s e2 = ok (Vbool z2).
Proof.
  t_xrbindP=> v1 Hv1 v2 Hv2; rewrite /sem_op2_b /mk_sem_sop2.
  t_xrbindP=> z1 Hz1 z2 Hz2 Hv.
  move: v1 Hv1 Hz1=> [] //; last by move=> [].
  move=> w1 Hw1 []Hz1; subst w1.
  move: v2 Hv2 Hz2=> [] //; last by move=> [].
  move=> w2 Hw2 []Hz1; subst w2.
  rewrite /sem_pexprs /= Hw1 /= Hw2 /=; eexists; eexists; eauto.
Qed.

Lemma sem_op1_w_dec gd sz v s e f:
  Let v1 := sem_pexpr gd s e in sem_op1_w f v1 = ok v ->
  exists sz' (z: word sz'), 
   [/\ (sz <= sz')%CMP, Vword (f (zero_extend sz z)) = v & sem_pexpr gd s e = ok (Vword z)].
Proof.
  t_xrbindP=> v1 Hv1; rewrite /sem_op1_w /mk_sem_sop1.
  t_xrbindP=> z1 /of_val_word [sz1 [w1 [hle ???]]];subst.
  by rewrite Hv1;exists sz1, w1.
Qed.

Lemma sem_op2_w_dec gd sz v e1 e2 s (f: word sz → word sz → _):
  Let v1 := sem_pexpr gd s e1 in (Let v2 := sem_pexpr gd s e2 in sem_op2_w f v1 v2) = ok v ->
  ∃ sz1 (z1: word sz1) sz2 (z2: word sz2),
   [/\ (sz <= sz1)%CMP, (sz <= sz2)%CMP, 
    Vword (f (zero_extend _ z1) (zero_extend _ z2)) = v &
    sem_pexprs gd s [:: e1; e2] = ok [:: Vword z1; Vword z2] ].
Proof.
  rewrite /sem_op2_w /mk_sem_sop2.
  t_xrbindP=> v1 Hv1 v2 Hv2 z1 /of_val_word [sz1 [w1 [Hw1 ??]]];subst.
  move=> z2 /of_val_word [sz2 [w2 [Hw2 ??]]] ?;subst.
  rewrite /sem_pexprs /= Hv1 /= Hv2 /=.
  by exists sz1, w1, sz2, w2.
Qed.

Lemma sem_op2_wb_dec gd sz v e1 e2 s f:
  Let v1 := sem_pexpr gd s e1 in (Let v2 := sem_pexpr gd s e2 in sem_op2_wb f v1 v2) = ok v ->
  ∃ sz1 (z1: word sz1) sz2 (z2: word sz2),
    Vbool (f (zero_extend sz z1) (zero_extend sz z2)) = v
    ∧ (sz ≤ sz1)%CMP ∧ (sz ≤ sz2)%CMP
    ∧ sem_pexprs gd s [:: e1; e2] = ok [:: Vword z1; Vword z2].
Proof.
  rewrite /sem_op2_wb /mk_sem_sop2.
  t_xrbindP=> v1 Hv1 v2 Hv2 z1 /of_val_word [sz1 [w1 [Hw1 ??]]].
  move=> z2 /of_val_word [sz2 [w2 [Hw2 ??]]] ?;subst.
  rewrite /sem_pexprs /= Hv1 /= Hv2 /=.
  by exists sz1, w1, sz2, w2.
Qed.

Definition eq_on (s : Sv.t) (vm1 vm2 : vmap) :=
  forall x, Sv.In x s -> vm1.[x]%vmap = vm2.[x]%vmap.

Notation "vm1 '=[' s ']' vm2" := (eq_on s vm1 vm2) (at level 70, vm2 at next level,
  format "'[hv ' vm1  =[ s ]  '/'  vm2 ']'").

Lemma eq_onT s vm1 vm2 vm3:
  vm1 =[s] vm2 -> vm2 =[s] vm3 -> vm1 =[s] vm3.
Proof. by move=> H1 H2 x Hin;rewrite H1 ?H2. Qed.

Lemma eq_onI s1 s2 vm1 vm2 : Sv.Subset s1 s2 -> vm1 =[s2] vm2 -> vm1 =[s1] vm2.
Proof. move=> Hs Heq x Hin;apply Heq;SvD.fsetdec. Qed.

Lemma eq_onS vm1 s vm2 : vm1 =[s] vm2 -> vm2 =[s] vm1.
Proof. by move=> Heq x Hin;rewrite Heq. Qed.

Global Instance equiv_eq_on s: Equivalence (eq_on s).
Proof.
  constructor=> //.
  move=> ??;apply: eq_onS.
  move=> ???;apply: eq_onT.
Qed.

Global Instance eq_on_impl : Proper (Basics.flip Sv.Subset ==> eq ==> eq ==> Basics.impl) eq_on.
Proof. by move=> s1 s2 H vm1 ? <- vm2 ? <-;apply: eq_onI. Qed.

Global Instance eq_on_m : Proper (Sv.Equal ==> eq ==> eq ==> iff) eq_on.
Proof. by move=> s1 s2 Heq vm1 ? <- vm2 ? <-;split;apply: eq_onI;rewrite Heq. Qed.

Lemma size_wrange d z1 z2 :
  size (wrange d z1 z2) = Z.to_nat (z2 - z1).
Proof. by case: d => /=; rewrite ?size_rev size_map size_iota. Qed.

Lemma nth_wrange z0 d z1 z2 n : (n < Z.to_nat (z2 - z1))%nat ->
  nth z0 (wrange d z1 z2) n =
    if   d is UpTo
    then z1 + Z.of_nat n
    else z2 - Z.of_nat n.
Proof.
case: d => ltn /=;
  by rewrite (nth_map 0%nat) ?size_iota ?nth_iota.
Qed.

Lemma last_wrange_up_ne z0 lo hi :
  lo < hi -> last z0 (wrange UpTo lo hi) = hi - 1.
Proof.
move=> lt; rewrite -nth_last nth_wrange; last rewrite size_wrange prednK //.
rewrite size_wrange -subn1 Nat2Z.inj_sub; first by rewrite Z2Nat.id; lia.
+ apply/leP/ltP; rewrite -Z2Nat.inj_0; apply Z2Nat.inj_lt; lia.
+ apply/ltP; rewrite -Z2Nat.inj_0; apply Z2Nat.inj_lt; lia.
Qed.

Lemma last_wrange_up lo hi : last (hi-1) (wrange UpTo lo hi) = hi - 1.
Proof.
case: (Z_lt_le_dec lo hi) => [lt|le]; first by apply: last_wrange_up_ne.
rewrite -nth_last nth_default // size_wrange.
by rewrite [Z.to_nat _](_ : _ = 0%nat) ?Z_to_nat_le0 //; lia.
Qed.

Lemma wrange_cons lo hi : lo < hi ->
  lo - 1 :: wrange UpTo lo hi = wrange UpTo (lo - 1) hi.
Proof.
set s1 := wrange _ _ _; set s2 := wrange _ _ _ => /=.
move=> lt; apply/(@eq_from_nth _ 0) => /=.
+ rewrite {}/s1 {}/s2 !size_wrange -Z2Nat.inj_succ; try lia.
  by apply: Nat2Z.inj; rewrite !Z2Nat.id; lia.
rewrite {1}/s1 size_wrange; case => [|i].
+ rewrite /s2 nth_wrange /=; try lia.
  by rewrite -Z2Nat.inj_0; apply/leP/Z2Nat.inj_lt; lia.
move=> lti; rewrite -[nth _ (_ :: _) _]/(nth 0 s1 i) {}/s1 {}/s2.
rewrite !nth_wrange; first lia; last first.
+ by apply/leP; move/leP: lti; lia.
apply/leP/Nat2Z.inj_lt; rewrite Z2Nat.id; try lia.
move/leP/Nat2Z.inj_lt: lti; try rewrite -Z2Nat.inj_succ; try lia.
by rewrite Z2Nat.id; lia.
Qed.

(* -------------------------------------------------------------------- *)

Lemma sem_app P gd l1 l2 s1 s2 s3:
  sem P gd s1 l1 s2 -> sem P gd s2 l2 s3 ->
  sem P gd s1 (l1 ++ l2) s3.
Proof.
  elim: l1 s1;first by move=> s1 H1;inversion H1.
  move=> a l Hrec s1 H1;inversion H1;subst;clear H1 => /= Hl2.
  by apply (Eseq H3);apply Hrec.
Qed.

Lemma sem_seq1 P gd i s1 s2:
  sem_I P gd s1 i s2 -> sem P gd s1 [::i] s2.
Proof.
  move=> Hi; apply (Eseq Hi);constructor.
Qed.

Definition vmap_eq_except (s : Sv.t) (vm1 vm2 : vmap) :=
  forall x, ~Sv.In x s -> vm1.[x]%vmap = vm2.[x]%vmap.

Notation "vm1 = vm2 [\ s ]" := (vmap_eq_except s vm1 vm2) (at level 70, vm2 at next level,
  format "'[hv ' vm1  '/' =  vm2  '/' [\ s ] ']'").

Lemma vmap_eq_exceptT vm2 s vm1 vm3:
  vm1 = vm2 [\s] -> vm2 = vm3 [\s] -> vm1 = vm3 [\s].
Proof. by move=> H1 H2 x Hin;rewrite H1 ?H2. Qed.

Lemma vmap_eq_exceptI s1 s2 vm1 vm2 : Sv.Subset s1 s2 -> vm1 = vm2 [\s1] -> vm1 = vm2 [\s2].
Proof. move=> Hs Heq x Hin;apply Heq;SvD.fsetdec. Qed.

Lemma vmap_eq_exceptS vm1 s vm2 : vm1 = vm2 [\s] -> vm2 = vm1 [\s].
Proof. by move=> Heq x Hin;rewrite Heq. Qed.

Global Instance equiv_vmap_eq_except s: Equivalence (vmap_eq_except s).
Proof.
  constructor=> //.
  move=> ??;apply: vmap_eq_exceptS.
  move=> ???;apply: vmap_eq_exceptT.
Qed.

Global Instance vmap_eq_except_impl :
  Proper (Sv.Subset ==> eq ==> eq ==> Basics.impl) vmap_eq_except.
Proof. by move=> s1 s2 H vm1 ? <- vm2 ? <-;apply: vmap_eq_exceptI. Qed.

Global Instance vmap_eq_except_m : Proper (Sv.Equal ==> eq ==> eq ==> iff) vmap_eq_except.
Proof. by move=> s1 s2 Heq vm1 ? <- vm2 ? <-;split;apply: vmap_eq_exceptI;rewrite Heq. Qed.

Lemma vrvP_var (x:var_i) v s1 s2 :
  write_var x v s1 = ok s2 ->
  s1.(evm) = s2.(evm) [\ Sv.add x Sv.empty].
Proof.
  rewrite /write_var;t_xrbindP => vm.
  by apply: set_varP => [t | _] => ? <- <- z Hz; rewrite Fv.setP_neq //;apply /eqP; SvD.fsetdec.
Qed.

Lemma write_noneP s s' ty v:
  write_none s ty v = ok s' ->
  s' = s /\
  ((exists u, pof_val ty v = ok u) \/ pof_val ty v = Error ErrAddrUndef ∧ ~~ is_sword ty ).
Proof.
  apply: on_vuP => [u ? -> | ?].
  + by split => //;left;exists u.
  by case:ifPn => // /eqP ? [->]; split => //; right.
Qed.

Lemma vrvP gd (x:lval) v s1 s2 :
  write_lval gd x v s1 = ok s2 ->
  s1.(evm) = s2.(evm) [\ vrv x].
Proof.
  case x => /= [ _ ty | ? /vrvP_var| sz y e| y e] //.
  + by move=> /write_noneP [->].
  + by t_xrbindP => ptr yv hyv hptr ptr' ev hev hptr' w hw m hm <-.
  apply: on_arr_varP => sz' n t; case: y => -[] ty yn yi /= -> Hy.
  apply: rbindP => we;apply: rbindP => ve He Hve.
  apply: rbindP => v0 Hv0;apply rbindP => t' Ht'.
  rewrite /set_var /= eq_dec_refl.
  case: CEDecStype.pos_dec => //= H [<-] /=.
  by move=> z Hz;rewrite Fv.setP_neq //;apply /eqP; SvD.fsetdec.
Qed.

Lemma vrvsP gd xs vs s1 s2 :
  write_lvals gd s1 xs vs = ok s2 ->
  s1.(evm) = s2.(evm) [\ vrvs xs].
Proof.
  elim: xs vs s1 s2 => [|x xs Hrec] [|v vs] s1 s2 //=.
  + by move=> [<-].
  apply: rbindP => s /vrvP Hrv /Hrec Hrvs.
  rewrite vrvs_cons;apply: (@vmap_eq_exceptT (evm s)).
  + by apply: vmap_eq_exceptI Hrv;SvD.fsetdec.
  by apply: vmap_eq_exceptI Hrvs;SvD.fsetdec.
Qed.

Lemma writeP P gd c s1 s2 :
   sem P gd s1 c s2 -> s1.(evm) = s2.(evm) [\ write_c c].
Proof.
  apply (@sem_Ind P gd (fun s1 c s2 => s1.(evm) = s2.(evm) [\ write_c c])
                  (fun s1 i s2 => s1.(evm) = s2.(evm) [\ write_i i])
                  (fun s1 i s2 => s1.(evm) = s2.(evm) [\ write_I i])
                  (fun x ws s1 c s2 =>
                     s1.(evm) = s2.(evm) [\ (Sv.union (Sv.singleton x) (write_c c))])
                  (fun _ _ _ _ _ => True)) => {c s1 s2} //.
  + move=> s1 s2 s3 i c _ Hi _ Hc z;rewrite write_c_cons => Hnin.
    by rewrite Hi ?Hc //;SvD.fsetdec.
  + move=> s1 s2 x tag ty e v ? hty Hw z.
    by rewrite write_i_assgn;apply (vrvP Hw).
  + move=> s1 s2 t o xs es; rewrite /sem_sopn.
    case: (Let _ := sem_pexprs _ _ _ in _) => //= vs Hw z.
    by rewrite write_i_opn;apply (vrvsP Hw).
  + by move=> s1 s2 e c1 c2 _ _ Hrec z;rewrite write_i_if => Hnin;apply Hrec;SvD.fsetdec.
  + by move=> s1 s2 e c1 c2 _ _ Hrec z;rewrite write_i_if => Hnin;apply Hrec;SvD.fsetdec.
  + by move=> s1 s2 s3 s4 c e c' _ Hc _ _ Hc' _ Hw z Hnin; rewrite Hc ?Hc' ?Hw //;
     move: Hnin; rewrite write_i_while; SvD.fsetdec.
  + move=> s1 s2 c e c' _ Hc _ z Hnin; rewrite Hc //.
    by move: Hnin; rewrite write_i_while; SvD.fsetdec.
  + by move=> s1 s2 i d lo hi c vlo vhi _ _ _ Hrec z;rewrite write_i_for;apply Hrec.
  + move=> s1 s1' s2 s3 i w ws c Hw _ Hc _ Hf z Hnin.
    by rewrite (vrvP_var Hw) ?Hc ?Hf //;SvD.fsetdec.
  move=> s1 m2 s2 ii xs fn args vargs vs _ _ _ Hw z.
  by rewrite write_i_call;apply (vrvsP Hw).
Qed.

Lemma write_IP P gd i s1 s2 :
   sem_I P gd s1 i s2 -> s1.(evm) = s2.(evm) [\ write_I i].
Proof.
  move=> /sem_seq1 /writeP.
  have := write_c_cons i [::].
  move=> Heq H x Hx;apply H; SvD.fsetdec.
Qed.

Lemma write_iP P gd i s1 s2 :
   sem_i P gd s1 i s2 -> s1.(evm) = s2.(evm) [\ write_i i].
Proof. by move=> /EmkI -/(_ 1%positive) /write_IP. Qed.

Lemma disjoint_eq_on gd s r s1 s2 v:
  disjoint s (vrv r) ->
  write_lval gd r v s1 = ok s2 ->
  s1.(evm) =[s] s2.(evm).
Proof.
  move=> Hd /vrvP H z Hnin;apply H.
  move:Hd;rewrite /disjoint /is_true Sv.is_empty_spec;SvD.fsetdec.
Qed.

Lemma disjoint_eq_ons gd s r s1 s2 v:
  disjoint s (vrvs r) ->
  write_lvals gd s1 r v = ok s2 ->
  s1.(evm) =[s] s2.(evm).
Proof.
  move=> Hd /vrvsP H z Hnin;apply H.
  move:Hd;rewrite /disjoint /is_true Sv.is_empty_spec;SvD.fsetdec.
Qed.

Lemma get_var_eq_on s vm' vm v: Sv.In v s -> vm =[s]  vm' -> get_var vm v = get_var vm' v.
Proof. by move=> Hin Hvm;rewrite /get_var Hvm. Qed.

Lemma on_arr_var_eq_on s' X s A x (f: ∀ sz n, Array.array n (word sz) → exec A) :
   evm s =[X] evm s' -> Sv.In x X ->
   on_arr_var s x f = on_arr_var s' x f.
Proof.
  by move=> Heq Hin;rewrite /on_arr_var;rewrite (get_var_eq_on Hin Heq).
Qed.

Lemma read_e_eq_on gd s vm' vm m e:
  vm =[read_e_rec s e] vm'->
  sem_pexpr gd (Estate m vm) e = sem_pexpr gd (Estate m vm') e.
Proof.
  elim:e s => //= [sz e He|v|v e He|sz v e He|o e He|o e1 He1 e2 He2| e He e1 He1 e2 He2] s.
  + by move=> /He ->.
  + by move=> /get_var_eq_on -> //;SvD.fsetdec.
  + move=> Heq;rewrite (He _ Heq)=> {He}.
    rewrite (@on_arr_var_eq_on
      {| emem := m; evm := vm' |} _ {| emem := m; evm := vm |} _ _ _ Heq) ?read_eE //.
    by SvD.fsetdec.
  + by move=> Hvm;rewrite (get_var_eq_on _ Hvm) ?(He _ Hvm) // read_eE;SvD.fsetdec.
  + by move=> /He ->.
  + move=> Heq;rewrite (He1 _ Heq) (He2 s) //.
    by move=> z Hin;apply Heq;rewrite read_eE;SvD.fsetdec.
  move=> Heq; rewrite (He _ Heq) (He1 s) ? (He2 s) //.
  + move=> z Hin;apply Heq;rewrite !read_eE.
    by move: Hin;rewrite read_eE;SvD.fsetdec.
  move=> z Hin;apply Heq;rewrite !read_eE.
  by move: Hin;rewrite read_eE;SvD.fsetdec.
Qed.

Lemma read_es_eq_on gd es s m vm vm':
  vm =[read_es_rec s es] vm'->
  sem_pexprs gd (Estate m vm) es = sem_pexprs gd (Estate m vm') es.
Proof.
  rewrite /sem_pexprs;elim: es s => //= e es Hes s Heq.
  rewrite (@read_e_eq_on _ s vm').
  + by case:sem_pexpr => //= v;rewrite (Hes (read_e_rec s e)).
  by move=> z Hin;apply Heq;rewrite read_esE;SvD.fsetdec.
Qed.

Lemma set_var_eq_on s x v vm1 vm2 vm1':
  set_var vm1 x v = ok vm2 ->
  vm1 =[s]  vm1' ->
  exists vm2' : vmap,
     vm2 =[Sv.union (Sv.add x Sv.empty) s]  vm2' /\
     set_var vm1' x v = ok vm2'.
Proof.
  (apply: set_varP;rewrite /set_var) => [t | /negbTE ->] -> <- hvm /=. 
  + exists (vm1'.[x <- ok t])%vmap;split => // z hin.
    case: (x =P z) => [<- | /eqP Hxz];first by rewrite !Fv.setP_eq.
    by rewrite !Fv.setP_neq ?hvm //;move/eqP:Hxz; SvD.fsetdec.
  exists (vm1'.[x <- pundef_addr (vtype x)])%vmap;split => // z Hin.
  case: (x =P z) => [<- | /eqP Hxz];first by rewrite !Fv.setP_eq.
  by rewrite !Fv.setP_neq ?hvm //;move/eqP:Hxz; SvD.fsetdec.
Qed.

Lemma write_var_eq_on X x v s1 s2 vm1:
  write_var x v s1 = ok s2 ->
  evm s1 =[X] vm1 ->
  exists vm2 : vmap,
    evm s2 =[Sv.add x X]  vm2 /\
    write_var x v {| emem := emem s1; evm := vm1 |} = ok {| emem := emem s2; evm := vm2 |}.
Proof.
  rewrite /write_var /=;t_xrbindP => vm2 Hset <-.
  move=> /(set_var_eq_on Hset) [vm2' [Hvm2 ->]];exists vm2';split=>//=.
  by apply: eq_onI Hvm2;SvD.fsetdec.
Qed.

Lemma write_lval_eq_on gd X x v s1 s2 vm1 :
  Sv.Subset (read_rv x) X ->
  write_lval gd x v s1 = ok s2 ->
  evm s1 =[X] vm1 ->
  exists vm2 : vmap,
   evm s2 =[Sv.union (vrv x) X] vm2 /\
   write_lval gd x v {|emem:= emem s1; evm := vm1|} = ok {|emem:= emem s2; evm := vm2|}.
Proof.
  case:x => [vi ty | x | sz x e | x e ] /=.
  + move=> ? /write_noneP [->];rewrite /write_none=> H ?;exists vm1;split=>//.
    by case:H => [[u ->] | [-> /negbTE -> ]].
  + move=> _ Hw /(write_var_eq_on Hw) [vm2 [Hvm2 Hx]];exists vm2;split=>//.
    by apply: eq_onI Hvm2;SvD.fsetdec.
  + rewrite read_eE => Hsub Hsem Hvm;move:Hsem.
    rewrite -(get_var_eq_on _ Hvm);last by SvD.fsetdec.
    rewrite (get_var_eq_on _ Hvm);last by SvD.fsetdec.
    case: s1 Hvm => sm1 svm1 Hvm1.
    rewrite (@read_e_eq_on gd Sv.empty vm1 svm1);first last.
    + by apply: eq_onI Hvm1;rewrite read_eE;SvD.fsetdec.
    apply: rbindP => vx ->;apply: rbindP => ve ->;apply: rbindP => w /= ->.
    by apply: rbindP => m /= -> [<-] /=;exists vm1.
  rewrite read_eE=> Hsub Hsem Hvm;move:Hsem.
  rewrite (@on_arr_var_eq_on {| emem := emem s1; evm := vm1 |} X s1 _ _ _ Hvm);
    last by SvD.fsetdec.
  case: s1 Hvm => sm1 svm1 Hvm1.
  rewrite (@read_e_eq_on gd (Sv.add x Sv.empty) vm1) /=;first last.
  + by apply: eq_onI Hvm1;rewrite read_eE.
  apply: on_arr_varP => sz n t Htx; rewrite /on_arr_var => -> /=.
  apply: rbindP => i -> /=;apply: rbindP => ? -> /=;apply: rbindP => ? -> /=.
  apply: rbindP => ? /set_var_eq_on -/(_ _ _ Hvm1) [vm2' [Heq' ->]] [] <-.
  by exists vm2'.
Qed.

Lemma write_lvals_eq_on gd X xs vs s1 s2 vm1 :
  Sv.Subset (read_rvs xs) X ->
  write_lvals gd s1 xs vs = ok s2 ->
  evm s1 =[X] vm1 ->
  exists vm2 : vmap,
    evm s2 =[Sv.union (vrvs xs) X] vm2 /\
    write_lvals gd {| emem:= emem s1; evm := vm1|} xs vs = ok {|emem:= emem s2; evm := vm2|}.
Proof.
  elim: xs vs X s1 s2 vm1 => [ | x xs Hrec] [ | v vs] //= X s1 s2 vm1.
  + by move=> _ [<-] ?;exists vm1.
  rewrite read_rvs_cons => Hsub.
  apply: rbindP => s1' Hw Hws /(write_lval_eq_on _ Hw) [ |vm1' [Hvm1' ->]].
  + by SvD.fsetdec.
  have [ |vm2 [Hvm2 /= ->]]:= Hrec _ _ _ _ _ _ Hws Hvm1';first by SvD.fsetdec.
  by exists vm2;split => //;rewrite vrvs_cons;apply: eq_onI Hvm2;SvD.fsetdec.
Qed.

Notation "vm1 = vm2 [\ s ]" := (vmap_eq_except s vm1 vm2) (at level 70, vm2 at next level,
  format "'[hv ' vm1  '/' =  vm2  '/' [\ s ] ']'").

Notation "vm1 '=[' s ']' vm2" := (eq_on s vm1 vm2) (at level 70, vm2 at next level,
  format "'[hv ' vm1  =[ s ]  '/'  vm2 ']'").

Definition word_uincl sz1 sz2 (w1:word sz1) (w2:word sz2) := 
  (sz1 <= sz2)%CMP && (w1 == zero_extend sz1 w2).

Lemma word_uincl_refl s (w : word s): word_uincl w w.
Proof. by rewrite /word_uincl zero_extend_u cmp_le_refl eqxx. Qed.
Hint Resolve word_uincl_refl.

Lemma word_uincl_eq s (w w': word s):
  word_uincl w w' → w = w'.
Proof. by move=> /andP [] _ /eqP; rewrite zero_extend_u. Qed.

Lemma word_uincl_trans s2 w2 s1 s3 w1 w3 :
   @word_uincl s1 s2 w1 w2 -> @word_uincl s2 s3 w2 w3 -> word_uincl w1 w3.
Proof.
  rewrite /word_uincl => /andP [hle1 /eqP ->] /andP [hle2 /eqP ->].
  by rewrite (cmp_le_trans hle1 hle2) zero_extend_idem // eqxx.
Qed.

Definition value_uincl (v1 v2:value) :=
  match v1, v2 with
  | Vbool b1, Vbool b2 => b1 = b2
  | Vint n1, Vint n2   => n1 = n2
  | Varr sz1 n1 t1, Varr sz2 n2 t2 =>
    n1 = n2 ∧
    ∃ e : sz1 = sz2,
    ∀ i v, Array.get t1 i = ok v → Array.get t2 i = ok (eq_rect _ word v _ e)
  | Vword sz1 w1, Vword sz2 w2 => word_uincl w1 w2
  | Vundef t, _     => vundef_type t = vundef_type (type_of_val v2)
  | _, _ => False
  end.

Lemma vundef_type_idem v : vundef_type v = vundef_type (vundef_type v).
Proof. by case: v. Qed.

Lemma value_uincl_refl v: @value_uincl v v.
Proof.
case: v => //=; last exact: vundef_type_idem.
by move => sz n a;split => //; exists erefl.
Qed.

Hint Resolve value_uincl_refl.

Lemma value_uincl_trans v2 v1 v3 : 
  value_uincl v1 v2 ->
  value_uincl v2 v3 ->
  value_uincl v1 v3.
Proof.
case: v1; case: v2 => //=; last (by move => s s'; rewrite -vundef_type_idem => ->);
  case: v3 => //=.
  + by move=> ??? ->.
  + by move=> ??? ->.
  + move=> ????????? [?] [? H1] [?] [? H2];subst;split => //.
    by exists erefl => ?? /H1 /H2. 
  + by move=> //= ??????;apply word_uincl_trans.
  by move=> ??????? -> [->] [??];subst.
Qed.

Lemma of_val_undef t t':
  of_val t (Vundef t') = Error (if subtype t t' then ErrAddrUndef else ErrType).
Proof.
case: t t' => [[]|[]||?[]] //=.
+ move=> sz p [] // sz' p'.
  have <- : (sarr sz p == sarr sz' p') = (sz == sz') && (p == p').
  + case: (sarr _ _ =P _) => //.
    + by move=> [] -> ->;rewrite !eqxx.
    by case: eqP => //= ->;case:eqP => //= ->.
  by case:ifP.    
by move=> ?;case:ifP.
Qed.

Lemma of_val_undef_ok t t' v:
  of_val t (Vundef t') <> ok v.
Proof. by case: t t' v => //= [||s p|s] [] //= *;case: ifP. Qed.

Lemma pof_val_undef_ok t t' v:
  pof_val t (Vundef t') <> ok v.
Proof. by case: t t' v => //= [||s p|s] [] //= *;case: ifP. Qed.

Lemma of_val_Vword t s1 (w1:word s1) w2 : of_val t (Vword w1) = ok w2 ->
  exists s2 (e:t = sword s2), 
    (s2 <= s1)%CMP /\  eq_rect t sem_t w2 _ e = zero_extend s2 w1.
Proof.
  case: t w2 => //= s2 w2 /truncate_wordP [] hle ->.
  by exists s2, erefl.
Qed.

Definition val_uincl (t1 t2:stype) (v1:sem_t t1) (v2:sem_t t2) :=
  value_uincl (to_val v1) (to_val v2).

Definition pval_uincl (t1 t2:stype) (v1:psem_t t1) (v2:psem_t t2) :=
  value_uincl (pto_val v1) (pto_val v2).

Definition eval_uincl (t1 t2:stype) (v1: exec (psem_t t1)) (v2: exec (psem_t t2)) :=
  match v1, v2 with
  | Ok  v1 , Ok   v2 => pval_uincl v1 v2
  | Error ErrAddrUndef, Ok    _ => True
  | Error x, Error y => x = y
  | _      , _       => False
  end.

Definition vm_uincl (vm1 vm2:vmap) :=
  forall x, eval_uincl (vm1.[x])%vmap (vm2.[x])%vmap.

Lemma val_uincl_refl t v: @val_uincl t t v v.
Proof. by rewrite /val_uincl. Qed.
Hint Resolve val_uincl_refl.

Lemma pval_uincl_refl t v: @pval_uincl t t v v.
Proof.  by rewrite /pval_uincl. Qed.
Hint Resolve pval_uincl_refl.

Lemma eval_uincl_refl t v: @eval_uincl t t v v.
Proof. by case: v=> //= -[]. Qed.
Hint Resolve eval_uincl_refl.

Lemma eval_uincl_trans t (v2 v1 v3: exec (psem_t t)) : 
   eval_uincl v1 v2 -> eval_uincl v2 v3 -> eval_uincl v1 v3.
Proof.
  case: v1 => /= [v1 | ].
  + by case: v2 => //= v2; case: v3 => // v3;apply: value_uincl_trans.
  case: v2 => [v2 [] // _| ];first by case: v3.
  by move=> e1 e2 he;have <- : e2 = e1 by case: e2 he.
Qed.

Lemma vm_uincl_refl vm: @vm_uincl vm vm.
Proof. by done. Qed.
Hint Resolve vm_uincl_refl.

Lemma val_uincl_array sz n (a a' : Array.array n (word sz)) : 
  (∀ (i : Z) (v : word sz), Array.get a i = ok v → Array.get a' i = ok v) ->
  @val_uincl (sarr sz n) (sarr sz n) a a'.
Proof.
  move=> H;rewrite /val_uincl /=;split => //;exists erefl => //.
Qed.

Lemma of_val_uincl v v' t z:
  value_uincl v v' ->
  of_val t v = ok z ->
  exists z', of_val t v' = ok z' /\ val_uincl z z'.
Proof.
  case: v v'=> [b | n | sz n a | sz w | tv] [b' | n' | sz' n' a' | sz' w' | tv'] //=;
    try by move=> _ /of_val_undef_ok.
  + by move=> <- ->;eauto.
  + by move=> <- ->;eauto.
  + case => ? [?]; subst => H; case: t z => //= sz p a1.
    case: wsize_eq_dec => // ?; subst.
    case: CEDecStype.pos_dec => //= ?;subst => /= -[] <-;exists a'.
    by split => //;apply val_uincl_array.
  move=> /andP []hsz /eqP -> /of_val_Vword [] s2 [] ?;subst => /= -[] hle ->.
  rewrite /truncate_word (cmp_le_trans hle hsz) zero_extend_idem //.
  by eexists;split;first reflexivity.
Qed.

Lemma pof_val_uincl v v' t z:
  value_uincl v v' ->
  pof_val t v = ok z ->
  exists z', pof_val t v' = ok z' /\ pval_uincl z z'.
Proof.
  case: v v'=> [b | n | sz n a | sz w | tv] [b' | n' | sz' n' a' | sz' w' | tv'] //=;
    try by move=> _ /pof_val_undef_ok.
  + by move=> <- ?;exists z.
  + by move=> <- ?;exists z.
  + case => <- [?]; subst => H; case: t z => //= sz p a1.
    case: wsize_eq_dec => // ?; subst.
    case: CEDecStype.pos_dec => //= Heq;subst=> /= -[] <-;exists a'.
    by split => //;apply val_uincl_array.
  move=> /andP []hsz /eqP ->;rewrite /pof_val /pval_uincl /=.
  case: t z => //= s z.
  case: (Sumbool.sumbool_of_bool (sz ≤ s)%CMP).
  + move=> e [<-].
    case: (Sumbool.sumbool_of_bool (sz' ≤ s)%CMP).
    + move=> ?; eexists;split;first reflexivity => /=.
      by rewrite /word_uincl /= hsz eqxx.
    move=> /negbT hle;rewrite /truncate_word (cmp_le_antisym hle) /=;eexists;split;first reflexivity.
    by rewrite /word_uincl /= e zero_extend_idem // eqxx.
  move=> /negbT hlt1; have hle:= cmp_le_antisym hlt1; rewrite /truncate_word hle zero_extend_idem //= => -[<-].
  have hnle: (sz' <= s)%CMP = false.
  + apply negbTE;rewrite cmp_nle_lt.
    by apply: cmp_lt_le_trans hsz;rewrite -cmp_nle_lt.
  rewrite (sumbool_of_boolEF hnle) (cmp_le_trans hle hsz) /=.
  by eexists;split;first reflexivity.
Qed.

Lemma value_uincl_int1 z v : value_uincl (Vint z) v -> v = Vint z.
Proof. by case: v => //= ? ->. Qed.

Lemma value_uincl_int ve ve' z :
  value_uincl ve ve' -> to_int ve = ok z -> ve = z /\ ve' = z.
Proof. by case: ve => // [ b' /value_uincl_int1 -> [->]| []//]. Qed.

Lemma value_uincl_word ve ve' sz (w: word sz) :
  value_uincl ve ve' →
  to_word sz ve = ok w →
  to_word sz ve' = ok w.
Proof.
case: ve ve' => //=.
+ move => sz' w' [] // sz1 w1 /andP [] hle /eqP -> /truncate_wordP [] hle'.
  by rewrite zero_extend_idem // => -> /=; rewrite /truncate_word (cmp_le_trans hle' hle).
by case => // sz' ve' _; case: ifP.
Qed.

Lemma value_uincl_bool1 b v : value_uincl (Vbool b) v -> v = Vbool b.
Proof. by case: v => //= ? ->. Qed.

Lemma value_uincl_bool ve ve' b :
  value_uincl ve ve' -> to_bool ve = ok b -> ve = b /\ ve' = b.
Proof. by case: ve => // [ b' /value_uincl_bool1 -> [->]| []//]. Qed.

Lemma subtype_vundef_type_eq t1 t2:
  subtype (vundef_type t1) t2 ->
  vundef_type t1 = vundef_type t2.
Proof. by case: t1;case: t2 => //= ???? /eqP. Qed.

Lemma subtype_vundef_type t : subtype (vundef_type t) t.
Proof. case: t => //=;apply wsize_le_U8. Qed.

Lemma subtype_eq_vundef_type t t': subtype t t' -> vundef_type t = vundef_type t'.
Proof.
  move=> hsub.
  apply subtype_vundef_type_eq.
  apply: subtype_trans hsub;apply subtype_vundef_type.
Qed.

Lemma subtype_type_of_val t (v:psem_t t):
  subtype (type_of_val (pto_val v)) t.
Proof. by case: t v => //= s w; apply pw_proof. Qed.

Lemma get_var_uincl x vm1 vm2 v1:
  vm_uincl vm1 vm2 ->
  get_var vm1 x = ok v1 ->
  exists v2, get_var vm2 x = ok v2 /\ value_uincl v1 v2.
Proof.
  move=> /(_ x);rewrite /get_var=> H; apply: on_vuP.
  + move=> z1 Heq1 <-.
    move: H;rewrite Heq1=> {Heq1}.
    case: (vm2.[x])%vmap => //= z2 Hz2.
    by exists (pto_val z2);split => //;apply pval_uinclP.
  move=> Hvm1;move: H;rewrite Hvm1;case (vm2.[x])%vmap => //=.
  + move=> s _ [<-];exists (pto_val s);split => //=.
    symmetry;apply subtype_vundef_type_eq.
    apply: subtype_trans;last by apply: subtype_type_of_val.
    apply subtype_vundef_type.
  by move=> e <- [<-];exists (Vundef (vtype x)).
Qed.

Lemma  get_vars_uincl (xs:seq var_i) vm1 vm2 vs1:
  vm_uincl vm1 vm2 ->
  mapM (fun x => get_var vm1 (v_var x)) xs = ok vs1 ->
  exists vs2,
    mapM (fun x => get_var vm2 (v_var x)) xs = ok vs2 /\ List.Forall2 value_uincl vs1 vs2.
Proof.
  move=> Hvm;elim: xs vs1 => [ | x xs Hrec] /= ?.
  + move=> [<-];exists [::];split=>//; constructor.
  apply: rbindP => v1 /(get_var_uincl Hvm) [v2 [-> ?]].
  apply: rbindP => vs1 /Hrec [vs2 [-> ?]] [] <- /=;exists (v2::vs2);split=>//.
  by constructor.
Qed.

Lemma vuincl_sem_op2_b o ve1 ve1' ve2 ve2' v1 :
  value_uincl ve1 ve1' -> value_uincl ve2 ve2' -> sem_op2_b o ve1 ve2 = ok v1 ->
  sem_op2_b o ve1' ve2' = ok v1.
Proof.
  rewrite /sem_op2_b /= /mk_sem_sop2 => Hvu1 Hvu2.
  apply: rbindP => z1 /(value_uincl_bool Hvu1) [] _ ->.
  by apply: rbindP => z2 /(value_uincl_bool Hvu2) [] _ -> [] <-.
Qed.

Lemma vuincl_sem_op2_i o ve1 ve1' ve2 ve2' v1 :
  value_uincl ve1 ve1' -> value_uincl ve2 ve2' -> sem_op2_i o ve1 ve2 = ok v1 ->
  sem_op2_i o ve1' ve2' = ok v1.
Proof.
  rewrite /sem_op2_i /= /mk_sem_sop2 => Hvu1 Hvu2.
  apply: rbindP => z1 /(value_uincl_int Hvu1) [] _ ->.
  by apply: rbindP => z2 /(value_uincl_int Hvu2) [] _ -> [] <-.
Qed.

Lemma vuincl_sem_op2_w sz (o: word sz → _) ve1 ve1' ve2 ve2' v1 :
  value_uincl ve1 ve1' -> value_uincl ve2 ve2' -> sem_op2_w o ve1 ve2 = ok v1 ->
  sem_op2_w o ve1' ve2' = ok v1.
Proof.
  rewrite /sem_op2_w /= /mk_sem_sop2 => Hvu1 Hvu2.
  apply: rbindP => z1 /= /(value_uincl_word Hvu1) ->.
  by apply: rbindP => z2 /= /(value_uincl_word Hvu2) -> [<-].
Qed.

Lemma vuincl_sem_op2_ib o ve1 ve1' ve2 ve2' v1 :
  value_uincl ve1 ve1' -> value_uincl ve2 ve2' -> sem_op2_ib o ve1 ve2 = ok v1 ->
  sem_op2_ib o ve1' ve2' = ok v1.
Proof.
  rewrite /sem_op2_ib /= /mk_sem_sop2 => Hvu1 Hvu2.
  apply: rbindP => z1 /(value_uincl_int Hvu1) [] _ ->.
  by apply: rbindP => z2 /(value_uincl_int Hvu2) [] _ -> [] <- /=.
Qed.

Lemma vuincl_sem_op2_wb sz (o: word sz → _) ve1 ve1' ve2 ve2' v1 :
  value_uincl ve1 ve1' -> value_uincl ve2 ve2' -> sem_op2_wb o ve1 ve2 = ok v1 ->
  sem_op2_wb o ve1' ve2' = ok v1.
Proof.
  rewrite /sem_op2_wb /= /mk_sem_sop2 => Hvu1 Hvu2.
  apply: rbindP => z1 /(value_uincl_word Hvu1) /= ->.
  by apply: rbindP => z2 /(value_uincl_word Hvu2) /= -> [<-].
Qed.

Lemma vuincl_sem_op2_w8 sz (o: word sz → _) ve1 ve1' ve2 ve2' v1 :
  value_uincl ve1 ve1' -> value_uincl ve2 ve2' -> sem_op2_w8 o ve1 ve2 = ok v1 ->
  sem_op2_w8 o ve1' ve2' = ok v1.
Proof.
  rewrite /sem_op2_w8 /= /mk_sem_sop2 => Hvu1 Hvu2.
  apply: rbindP => z1 /(value_uincl_word Hvu1) /= ->.
  by apply: rbindP => z2 /(value_uincl_word Hvu2) /= -> [<-].
Qed.

Lemma vuincl_sem_sop2 o ve1 ve1' ve2 ve2' v1 :
  value_uincl ve1 ve1' -> value_uincl ve2 ve2' ->
  sem_sop2 o ve1 ve2 = ok v1 ->
  sem_sop2 o ve1' ve2' = ok v1.
Proof.
  case:o => [||[]|[]|[]|[]|[]|[]||||[]|[]|[]|[]|[]|[]]/=;
   eauto using vuincl_sem_op2_i, vuincl_sem_op2_w, vuincl_sem_op2_b, vuincl_sem_op2_ib,
    vuincl_sem_op2_wb, vuincl_sem_op2_w8.
Qed.

Lemma val_uincl_sword s (z z':sem_t (sword s)) : val_uincl z z' -> z = z'.
Proof.
  by rewrite /val_uincl /= /word_uincl cmp_le_refl zero_extend_u => /eqP.
Qed.

Lemma vuincl_sem_sop1 o ve1 ve1' v1 :
  value_uincl ve1 ve1' ->
  sem_sop1 o ve1 = ok v1 ->
  sem_sop1 o ve1' = ok v1.
Proof.
  case: o => [ | sz | [| sz] | sz ];
  rewrite /= /sem_op1_b /sem_op1_w /sem_op1_i /mk_sem_sop1 => Hu;
  apply: rbindP => z Hz; last case: z Hz => // p Hz; case => <-;
  last (by have [_ ->] := value_uincl_int Hu Hz);
  try (by have [z' [/= -> ->]] := of_val_uincl Hu Hz);
  by have [z' [/= -> /val_uincl_sword ->]] := of_val_uincl Hu Hz.
Qed.

Lemma value_uincl_subtype v1 v2 :
  value_uincl v1 v2 ->
  subtype (type_of_val v1) (type_of_val v2).
Proof.
case: v1 v2 => [ b | i | s n t | s w | ty ]; try by case.
+ by case => //= s' n' t' [?] [? _]; subst.
+ by case => //= s' w' /andP[].
move => /= v2 ->; exact: subtype_vundef_type.
Qed.

Lemma value_uincl_vundef_type_eq v1 v2 : 
  value_uincl v1 v2 -> 
  vundef_type (type_of_val v1) = vundef_type (type_of_val v2).
Proof. move /value_uincl_subtype; exact: subtype_eq_vundef_type. Qed.

Lemma sem_pexpr_uincl gd s1 vm2 e v1:
  vm_uincl s1.(evm) vm2 ->
  sem_pexpr gd s1 e = ok v1 ->
  exists v2, sem_pexpr gd (Estate s1.(emem) vm2) e = ok v2 /\ value_uincl v1 v2.
Proof.
  move=> Hu; elim: e v1=>//=[z|b|sz e He|x|g|x p Hp|sz x p Hp|o e He|o e1 He1 e2 He2| e He e1 He1 e2 He2 ] v1.
  + by move=> [] <-;exists z.
  + by move=> [] <-;exists b.
  + apply: rbindP => z;apply: rbindP => ve /He [] ve' [] -> Hvu Hto [] <-.
    by case: (value_uincl_int Hvu Hto) => ??;subst; exists (Vword (wrepr sz z)).
  + by apply get_var_uincl.
  + eauto.
  + apply on_arr_varP => sz n t Htx;rewrite /on_arr_var=> /(get_var_uincl Hu) [v2 [->]].
    case: v2 => //= sz' n' t' [?] [?]; subst => /= Htt'.
    apply: rbindP => z;apply: rbindP => vp /Hp [] vp' [] -> /= Hvu Hto.
    case: (value_uincl_int Hvu Hto) => ??;subst.
    apply: rbindP=> w /Htt' Hget [] <- /=; rewrite Hget /=.
    by exists (Vword w); split => //; exists erefl.
  + apply: rbindP => w1;apply: rbindP => vx /(get_var_uincl Hu) [vx' [->]].
    rewrite /to_pointer.
    move=> /value_uincl_word H/H{H} /= -> /=.
    apply: rbindP => wp;apply: rbindP => vp /Hp [] vp' [] ->.
    by move=> /value_uincl_word Hvu/Hvu {Hvu} /= -> /= ->; eauto.
  + apply: rbindP => ve1 /He [] ve1' [] -> /vuincl_sem_sop1 Hvu1 /Hvu1.
    by exists v1.
  + apply: rbindP => ve1 /He1 [] ve1' [] -> /vuincl_sem_sop2 Hvu1.
    apply: rbindP => ve2 /He2 [] ve2' [] -> /Hvu1 Hvu2 /Hvu2.
    by exists v1.
  apply: rbindP => b;apply:rbindP => wb /He [] ve' [] -> Hue'.
  move=> /value_uincl_bool -/(_ _ Hue') [??];subst wb ve' => /=.
  t_xrbindP => v2 /He1 [] v2' [] -> Hv2' v3 /He2 [] v3' [] -> Hv3'.
  case: ifP => //=.
  rewrite (value_uincl_vundef_type_eq Hv2') (value_uincl_vundef_type_eq Hv3') => -> [<-].
  eexists;split;first by eauto.
  by case b.
Qed.

Lemma sem_pexprs_uincl gd s1 vm2 es vs1:
  vm_uincl s1.(evm) vm2 ->
  sem_pexprs gd s1 es  = ok vs1 ->
  exists vs2, sem_pexprs gd (Estate s1.(emem) vm2) es = ok vs2 /\
              List.Forall2 value_uincl vs1 vs2.
Proof.
  rewrite /sem_pexprs; move=> Hvm;elim: es vs1 => [ | e es Hrec] vs1 /=.
  + by move=> [] <-;eauto.
  apply: rbindP => ve /(sem_pexpr_uincl Hvm) [] ve' [] -> ?.
  by apply: rbindP => ys /Hrec [vs2 []] /= -> ? [] <- /=;eauto.
Qed.

Definition is_w_or_b t :=
  match t with
  | sbool | sword _ => true
  | _             => false
  end.

Lemma vuincl_sopn ts o vs vs' v :
  all is_w_or_b ts ->
  List.Forall2 value_uincl vs vs' ->
  app_sopn ts o vs = ok v ->
  exists v' : values,
     app_sopn ts o vs' = ok v' /\ List.Forall2 value_uincl v v'.
Proof.
  elim: ts o vs vs' => /= [ | t ts Hrec] o vs vs' Hall Hu;sinversion Hu => //=.
  + move => ->;exists v;auto using List_Forall2_refl.
  move: Hall=> /andP [].
  case: t o => //= [ | sz ] o _ Hall; apply: rbindP.
  + by move=> b /(value_uincl_bool H) [] _ -> /= /(Hrec _ _ _ Hall H0).
  by move=> w /(value_uincl_word H) -> /= /(Hrec _ _ _ Hall H0).
Qed.

Lemma vuincl_exec_opn o vs vs' v :
  List.Forall2 value_uincl vs vs' -> exec_sopn o vs = ok v ->
  exists v', exec_sopn o vs' = ok v' /\ List.Forall2  value_uincl v v'.
Proof.
rewrite /sem_sopn; case: o; (try (refine (λ sz: wsize, _)));
try apply: vuincl_sopn => //.
move: vs=> [] // vs1 [] // vs2 [] // vs3 [] //.
case/List_Forall2_inv_l => vs'1 [?] [->] [H1].
case/List_Forall2_inv_l => vs'2 [?] [->] [H2].
case/List_Forall2_inv_l => vs'3 [?] [->] [H3].
move/List_Forall2_inv_l => -> /=.
t_xrbindP => b /(value_uincl_bool H1) [] _ -> /=.
by case: b; t_xrbindP => w hw <-;
rewrite (value_uincl_word _ hw) /=; eauto.
Qed.

Lemma set_vm_uincl vm vm' x z z' :
  vm_uincl vm vm' ->
  pval_uincl z z' ->
  vm_uincl (vm.[x <- ok z])%vmap (vm'.[x <- ok z'])%vmap.
Proof.
  move=> Hvm Hz y; case( x =P y) => [<- | /eqP Hneq];by rewrite ?Fv.setP_eq ?Fv.setP_neq.
Qed.

Lemma of_val_error t v:
  of_val t v = undef_error -> exists t', subtype (vundef_type t) t' /\ v = Vundef t'.
Proof.
case: t v => [||sz p|sz] [] //=.
+ by case => //;eauto.
+ by case => //;eauto.
+ move => sz' n a; case: wsize_eq_dec => // ?; subst.
  by case: CEDecStype.pos_dec.
+ by case => // ??;case:ifP => // /andP [] /eqP <- /eqP <-;eauto.
+ by move=> ??;rewrite /truncate_word;case:ifP.
case => // ? _;eexists;split;last reflexivity.
by apply wsize_le_U8.
Qed.

Lemma pof_val_error t v:
  pof_val t v = undef_error -> exists t', subtype (vundef_type t) t' /\ v = Vundef t'.
Proof.
case: t v => [||sz p|sz] [] //=.
+ by case => //;eauto.
+ by case => //;eauto.
+ move => sz' n a; case: wsize_eq_dec => // ?; subst.
  by case: CEDecStype.pos_dec.
+ by case => // ??;case:ifP => // /andP [] /eqP <- /eqP <-;eauto.
+ move=> s w.
  case: Sumbool.sumbool_of_bool => //=.
  by rewrite /truncate_word;case:ifP.
case => // s _;eexists;split;last reflexivity.
by apply wsize_le_U8.
Qed.

Lemma pof_val_type_of t v :
  vundef_type t = vundef_type (type_of_val v) ->
  (exists v', pof_val t v = ok v') \/ pof_val t v = undef_error.
Proof.
  case: t v => [||s1 p1| s1] /= [b | z | s2 p2 t2 | s2 w | tv] //=;try by left;eauto.
  + by case: tv => //=;eauto.
  + by case: tv => //=;eauto.
  + by move=> [] ??;subst s2 p2;rewrite eq_dec_refl pos_dec_n_n /=;eauto.
  + by case: tv => //= s2 p2 [] ??;subst;rewrite !eqxx /=;eauto.
  + move => _; case: Sumbool.sumbool_of_bool => [ e | /negbT ]; first by eauto.
    by rewrite /truncate_word => h; rewrite (cmp_le_antisym h) /=;eauto.
  by case: tv => //= s2 _;eauto.
Qed.

Lemma subtype_pof_val_ok t1 t2 v v1 : 
  subtype t1 t2 ->       
  pof_val t1 v = ok v1 ->
  exists v2, pof_val t2 v = ok v2 /\ value_uincl (pto_val v1) (pto_val v2).
Proof.
  case: t1 v1 => /= [v1 /eqP<-|v1 /eqP<-|s n v1 /eqP<- |s1 v1];
   try by move=> h;eexists;split;[apply h | done].
  + move=> h;eexists;split;first by apply h.
    by move=> /=;split=>//;exists erefl.
  case: t2 => //= s2 hle;case: v => //=;last by case.
  move=> s' w.
  case: Sumbool.sumbool_of_bool => e.
  + case: Sumbool.sumbool_of_bool => e'.
    + move=> [<-];eauto.
    by rewrite (cmp_le_trans e hle) in e'.
  move: e => /negbT ;rewrite cmp_nle_lt => e.
  t_xrbindP => w' /truncate_wordP [hle1 ?] ?;subst w' v1.
  case: Sumbool.sumbool_of_bool => e'.
  + eexists;split;first reflexivity.
    by rewrite /pword_of_word /= /word_uincl hle1 eqxx.
  move: e' => /negbT ;rewrite cmp_nle_lt => e'.
  rewrite /truncate_word (cmp_lt_le e') /= /pword_of_word. 
  eexists;split;first reflexivity.
  by rewrite /= /word_uincl hle zero_extend_idem // eqxx.
Qed.

Lemma pof_val_pto_val t (v:psem_t t): pof_val t (pto_val v) = ok v.
Proof. 
  case: t v => [b | z | s n a | s w] //=.
  + by rewrite eq_dec_refl pos_dec_n_n.
  case: Sumbool.sumbool_of_bool => e.
  f_equal;case: w e => /= ????;f_equal; apply eq_irrelevance.
  by have := pw_proof w;rewrite e. 
Qed.

Lemma value_uincl_pof_val t v1 (v1' v2 : psem_t t):
  pof_val t v1 = ok v1' ->
  value_uincl v1 (pto_val v2) ->
  value_uincl (pto_val v1') (pto_val v2).
Proof.
  case: t v1' v2 => /= [||s n|s] v1' v2.
  + by move=> /to_bool_inv ->.
  + by move=> h1 h2;have [? [<-]]:= value_uincl_int h2 h1.
  + by move=> /to_arr_ok ->.
  case: v1 => //= [ s' w| [] //].
  case: Sumbool.sumbool_of_bool => [ e | /negbT ].
  + by move=> [<-].
  rewrite cmp_nle_lt /truncate_word => hlt.
  have hle := cmp_lt_le hlt.
  by rewrite hle /= => -[<-] /=; apply word_uincl_trans;rewrite /word_uincl hle eqxx.
Qed.

Lemma apply_undef_pundef_addr t : apply_undef (pundef_addr t) = pundef_addr t.
Proof. by case: t. Qed.

Lemma eval_uincl_undef t (v:psem_t t) : eval_uincl (pundef_addr t) (ok v).
Proof.
  case: t v => //= sz p v;rewrite /pval_uincl /=;split => //.
  by exists erefl => i w H; have := Array.getP_empty H.
Qed.


Lemma eval_uincl_apply_undef t (v1 v2 : exec (psem_t t)): 
  eval_uincl v1 v2 -> 
  eval_uincl (apply_undef v1) (apply_undef v2).
Proof.
  case:v1 v2=> [v1 | []] [v2 | e2] //=; try by move=> <-.
  by move=> _; apply eval_uincl_undef.
Qed.

Lemma subtype_eval_uincl t t' (v:exec (psem_t t)):
  subtype (vundef_type t') t ->
  eval_uincl (pundef_addr t) v -> eval_uincl (pundef_addr t') v.
Proof.
  case: t' => /= [/eqP?|/eqP?|s n /eqP?| s];subst => //=.
  case: t v => //=.
Qed.

Lemma subtype_eval_uincl_pundef t1 t2 : 
  subtype t1 t2 -> 
  eval_uincl (pundef_addr t1) (pundef_addr t2).
Proof.
  case: t1 => /= [/eqP?|/eqP?|s n /eqP?| s];subst => //=.
  case: t2 => //=.
Qed.

Lemma set_var_uincl vm1 vm1' vm2 x v v' :
  vm_uincl vm1 vm1' ->
  value_uincl v v' ->
  set_var vm1 x v = ok vm2 ->
  exists vm2', set_var vm1' x v' = ok vm2' /\ vm_uincl vm2 vm2'.
Proof.
  (move=> Hvm Hv;apply set_varP;rewrite /set_var) => [t | /negbTE ->].
  + move=> /(pof_val_uincl Hv) [z' [-> ?]] <- /=.
    by exists (vm1'.[x <- ok z'])%vmap;split=>//; apply set_vm_uincl.
  move=> /pof_val_error [t' [/subtype_vundef_type_eq hle heq]] <-.
  move: Hv;rewrite heq /= -hle => /pof_val_type_of.
  by move=> [ [w] |] -> /=;eexists;(split;first by eauto) => z;case: (x =P z) => [<- |/eqP ? ];
    rewrite ?Fv.setP_eq ?Fv.setP_neq //;apply: eval_uincl_undef.
Qed.

Lemma Array_set_uincl sz n n' (a1 a1': Array.array n' (word sz))
                              (a2 : Array.array n' (word sz)) i v:
  @val_uincl (sarr sz n) (sarr sz n') a1 a2 ->
  Array.set a1 i v = ok a1' ->
  exists a2', Array.set a2 i v = ok a2' /\ @val_uincl (sarr sz n) (sarr sz n') a1' a2'.
Proof.
  rewrite /Array.set /val_uincl /= => -[ ? [heq]];subst.
  rewrite (Eqdep_dec.UIP_dec wsize_eq_dec heq erefl) /= => H.
  case:ifP=> //= ? [<-].
  exists (FArray.set a2 i (ok v));split => //;split => //;exists erefl => /=.
  move=> i' v';move: (H i' v').
  rewrite /Array.get;case:ifP=> //= Hbound.
  by rewrite !FArray.setP;case:ifP.
Qed.

Lemma write_var_uincl s1 s2 vm1 v1 v2 x :
  vm_uincl (evm s1) vm1 ->
  value_uincl v1 v2 ->
  write_var x v1 s1 = ok s2 ->
  exists vm2 : vmap,
    write_var x v2 {| emem := emem s1; evm := vm1 |} =
    ok {| emem := emem s2; evm := vm2 |} /\ vm_uincl (evm s2) vm2.
Proof.
  move=> Hvm1 Hv;rewrite /write_var;t_xrbindP => vm1' Hmv1' <- /=.
  have [vm2' [-> ?] /=] := set_var_uincl Hvm1 Hv Hmv1';eauto.
Qed.

Lemma write_vars_uincl s1 s2 vm1 vs1 vs2 xs :
  vm_uincl (evm s1) vm1 ->
  List.Forall2 value_uincl vs1 vs2 ->
  write_vars xs vs1 s1 = ok s2 ->
  exists vm2 : vmap,
    write_vars xs vs2 {| emem := emem s1; evm := vm1 |} =
    ok {| emem := emem s2; evm := vm2 |} /\ vm_uincl (evm s2) vm2.
Proof.
  elim: xs s1 vm1 vs1 vs2 => /= [ | x xs Hrec] s1 vm1 vs1 vs2 Hvm [] //=.
  + by move=> [] <-;eauto.
  move=> {vs1 vs2} v1 v2 vs1 vs2 Hv Hvs;apply: rbindP => s1'.
  by move=> /(write_var_uincl Hvm Hv) [] vm2 [] -> Hvm2 /(Hrec _ _ _ _ Hvm2 Hvs).
Qed.

Lemma vundef_type_nis_sword t: 
  ~~ is_sword t -> vundef_type t = t.
Proof. by case: t => //. Qed.

Lemma vundef_type_is_sword t1 t2: 
  vundef_type t1 = vundef_type t2 -> is_sword t1 = is_sword t2.
Proof. by case: t1;case: t2. Qed.

Lemma pof_val_type_of_val v:
  ~~ is_sword (type_of_val v) ->
  (∃ w : psem_t (type_of_val v), pof_val (type_of_val v) v = ok w) ∨ 
  pof_val (type_of_val v) v = undef_error.
Proof.
  case: v => [b|z|s n a|s w|s] //=;eauto.
  + by move=> _; rewrite eq_dec_refl pos_dec_n_n /=;eauto. 
  case: s => //=;eauto.
  by move=> ??;rewrite !eqxx /=;auto.
Qed.

Lemma pof_val_uincl_error v1 v2 t:
  ~~ is_sword t ->
  pof_val t v1 = undef_error ->
  value_uincl v1 v2 ->
  (exists w:psem_t t, pof_val t v2 = ok w) \/ pof_val t v2 = undef_error.
Proof.
  move=> hword /pof_val_error [t' [/subtype_vundef_type_eq hle ->]] /= htof.
  have heq : type_of_val v2 = t.
  + rewrite -(vundef_type_nis_sword hword) hle htof;symmetry.
    apply vundef_type_nis_sword.  
    by rewrite -(vundef_type_is_sword htof) -(vundef_type_is_sword hle).
  by subst;apply pof_val_type_of_val.  
Qed.
  
Lemma uincl_write_none s2 v1 v2 s s' t :
  value_uincl v1 v2 ->
  write_none s t v1 = ok s' ->
  write_none s2 t v2 = ok s2.
Proof.
  move=> Hv /write_noneP [_] H;rewrite /write_none.
  case:H.
  + by move=> [u] /(pof_val_uincl Hv) [u' [-> _]].
  move=> [] hof hw.
  have [ [w] -> // | -> ] /=:= pof_val_uincl_error hw hof Hv.
  by rewrite (negbTE hw).
Qed.

Lemma write_uincl gd s1 s2 vm1 r v1 v2:
  vm_uincl s1.(evm) vm1 ->
  value_uincl v1 v2 ->
  write_lval gd r v1 s1 = ok s2 ->
  exists vm2,
    write_lval gd r v2 (Estate (emem s1) vm1) = ok (Estate (emem s2) vm2) /\
    vm_uincl s2.(evm) vm2.
Proof.
  move=> Hvm1 Hv;case:r => [xi ty | x | sz x p | x p] /=.
  + move=> H; have [-> _]:= write_noneP H.
    by rewrite (uincl_write_none _ Hv H);exists vm1.
  + by apply write_var_uincl.
  + apply: rbindP => vx1; apply: rbindP => vx /(get_var_uincl Hvm1) [vx2 [-> Hvx]].
    rewrite /to_pointer /=.
    move=> /(value_uincl_word Hvx) -> {Hvx vx} /=.
    apply: rbindP => ve; apply: rbindP => ve' /(sem_pexpr_uincl Hvm1) [ve''] [] -> Hve.
    move=> /(value_uincl_word Hve) /= -> /=.
    apply: rbindP => w /(value_uincl_word Hv) -> /=.
    by apply: rbindP => m' -> [] <- /=;eauto.
  apply: on_arr_varP => sz n a Htx /(get_var_uincl Hvm1).
  rewrite /on_arr_var => -[] vx [] /= -> /=; case: vx => //= sz0 n0 t0 [] ? [?];subst.
  move=> /= /val_uincl_array Ht0.
  apply: rbindP => i;apply: rbindP=> vp /(sem_pexpr_uincl Hvm1) [vp' [-> Hvp]] /=.
  move=>  /(value_uincl_int Hvp) [] _ -> /=.
  apply: rbindP => v /(value_uincl_word Hv) -> /=.
  apply: rbindP => t /(Array_set_uincl Ht0).
  move=> [] t' [-> Ht];apply: rbindP => vm'.
  by move=> /(set_var_uincl Hvm1 Ht) /= [vm2' [-> ?]] [] <- /=;eauto.
Qed.

Lemma writes_uincl gd s1 s2 vm1 r v1 v2:
  vm_uincl s1.(evm) vm1 ->
  List.Forall2 value_uincl v1 v2 ->
  write_lvals gd s1 r v1 = ok s2 ->
  exists vm2,
    write_lvals gd (Estate (emem s1) vm1) r v2 = ok (Estate (emem s2) vm2) /\
    vm_uincl s2.(evm) vm2.
Proof.
  elim: r v1 v2 s1 s2 vm1 => [ | r rs Hrec] ?? s1 s2 vm1 Hvm1 /= [] //=.
  + by move=> [] <-;eauto.
  move=> v1 v2 vs1 vs2 Hv Hforall.
  apply: rbindP => z /(write_uincl Hvm1 Hv) [] vm2 [-> Hvm2].
  by move=> /(Hrec _ _ _ _ _ Hvm2 Hforall).
Qed.

Lemma write_vars_lvals gd xs vs s1:
  write_vars xs vs s1 = write_lvals gd s1 [seq Lvar i | i <- xs] vs.
Proof.
  rewrite /write_vars /write_lvals.
  elim: xs vs s1 => [ | x xs Hrec] [ | v vs] //= s1.
  by case: write_var => //=.
Qed.

Lemma sem_pexprs_get_var gd s xs :
  sem_pexprs gd s [seq Pvar i | i <- xs] = mapM (fun x : var_i => get_var (evm s) x) xs.
Proof.
  rewrite /sem_pexprs;elim: xs=> //= x xs Hrec.
  by case: get_var => //= v;rewrite Hrec.
Qed.

Section UNDEFINCL.

Variable (p:prog).
Context (gd: glob_defs).

Let Pc s1 c s2 :=
  forall vm1 ,
    vm_uincl (evm s1) vm1 ->
    exists vm2,
      sem p gd {|emem := emem s1; evm := vm1|} c {|emem := emem s2; evm := vm2|} /\
      vm_uincl (evm s2) vm2.

Let Pi_r s1 i s2 :=
  forall vm1,
    vm_uincl (evm s1) vm1 ->
    exists vm2,
      sem_i p gd {|emem := emem s1; evm := vm1|} i {|emem := emem s2; evm := vm2|} /\
      vm_uincl (evm s2) vm2.

Let Pi s1 i s2 :=
  forall vm1,
    vm_uincl (evm s1) vm1 ->
    exists vm2,
      sem_I p gd {|emem := emem s1; evm := vm1|} i {|emem := emem s2; evm := vm2|} /\
      vm_uincl (evm s2) vm2.

Let Pfor (i:var_i) zs s1 c s2 :=
  forall vm1,
    vm_uincl (evm s1) vm1 ->
    exists vm2,
      sem_for p gd i zs {|emem := emem s1; evm := vm1|} c {|emem := emem s2; evm := vm2|} /\
      vm_uincl (evm s2) vm2.

Let Pfun m1 fd vargs m2 vres :=
  forall vargs',
    List.Forall2 value_uincl vargs vargs' ->
    exists vres', 
      sem_call p gd m1 fd vargs' m2 vres' /\
      List.Forall2 value_uincl vres vres'.

Local Lemma Hnil s : @Pc s [::] s.
Proof. by move=> vm1 Hvm1;exists vm1;split=> //;constructor. Qed.

Local Lemma Hcons s1 s2 s3 i c :
  sem_I p gd s1 i s2 -> Pi s1 i s2 ->
  sem p gd s2 c s3 -> Pc s2 c s3 -> Pc s1 (i :: c) s3.
Proof.
  move=> _ Hi _ Hc vm1 /Hi [vm2 []] Hsi /Hc [vm3 []] Hsc ?.
  by exists vm3;split=>//;econstructor;eauto.
Qed.

Local Lemma HmkI ii i s1 s2 : sem_i p gd s1 i s2 -> Pi_r s1 i s2 -> Pi s1 (MkI ii i) s2.
Proof. by move=> _ Hi vm1 /Hi [vm2 []] Hsi ?;exists vm2. Qed.

Local Lemma Hasgn s1 s2 x tag ty e v :
  sem_pexpr gd s1 e = ok v ->
  check_ty_val ty v ->
  write_lval gd x v s1 = ok s2 ->
  Pi_r s1 (Cassgn x tag ty e) s2.
Proof.
  move=> hsem hty hwr vm1 Hvm1.
  have [v' [hsem' hle]]:= sem_pexpr_uincl Hvm1 hsem.
  have  [vm2 [Hw ?]]:= write_uincl Hvm1 hle hwr;exists vm2;split=> //.
  (econstructor;first exact hsem') => //.
  apply: (subtype_trans hty (value_uincl_subtype hle)).
Qed.

Local Lemma Hopn s1 s2 t o xs es:
  sem_sopn gd o s1 xs es = ok s2 ->
  Pi_r s1 (Copn xs t o es) s2.
Proof.
  move=> H vm1 Hvm1; apply: rbindP H => rs;apply: rbindP => vs.
  move=> /(sem_pexprs_uincl Hvm1) [] vs' [] H1 H2.
  move=> /(vuincl_exec_opn H2) [] rs' [] H3 H4.
  move=> /(writes_uincl Hvm1 H4) [] vm2 [] ??.
  exists vm2;split => //;constructor.
  by rewrite /sem_sopn H1 /= H3.
Qed.

Local Lemma Hif_true s1 s2 e c1 c2 :
  sem_pexpr gd s1 e = ok (Vbool true) ->
  sem p gd s1 c1 s2 -> Pc s1 c1 s2 -> Pi_r s1 (Cif e c1 c2) s2.
Proof.
  move=> H _ Hc vm1 Hvm1.
  have [v' [H1 /value_uincl_bool1 ?]]:= sem_pexpr_uincl Hvm1 H;subst v'.
  have [vm2 [??]]:= Hc _ Hvm1;exists vm2;split=>//.
  by apply Eif_true;rewrite // H1.
Qed.

Local Lemma Hif_false s1 s2 e c1 c2 :
  sem_pexpr gd s1 e = ok (Vbool false) ->
  sem p gd s1 c2 s2 -> Pc s1 c2 s2 -> Pi_r s1 (Cif e c1 c2) s2.
Proof.
  move=> H _ Hc vm1 Hvm1.
  have [v' [H1 /value_uincl_bool1 ?]]:= sem_pexpr_uincl Hvm1 H;subst v'.
  have [vm2 [??]]:= Hc _ Hvm1;exists vm2;split=>//.
  by apply Eif_false;rewrite // H1.
Qed.

Local Lemma Hwhile_true s1 s2 s3 s4 c e c' :
  sem p gd s1 c s2 -> Pc s1 c s2 ->
  sem_pexpr gd s2 e = ok (Vbool true) ->
  sem p gd s2 c' s3 -> Pc s2 c' s3 ->
  sem_i p gd s3 (Cwhile c e c') s4 -> Pi_r s3 (Cwhile c e c') s4 -> Pi_r s1 (Cwhile c e c') s4.
Proof.
  move=> _ Hc H _ Hc' _ Hw vm1 Hvm1. 
  have [vm2 [Hs2 Hvm2]] := Hc _ Hvm1.
  have [v' [H1 /value_uincl_bool1 ?]]:= sem_pexpr_uincl Hvm2 H;subst.
  have [vm3 [H4 /Hw [vm4] [??]]]:= Hc' _ Hvm2;exists vm4;split => //.
  by eapply Ewhile_true;eauto;rewrite H1.
Qed.

Local Lemma Hwhile_false s1 s2 c e c' :
  sem p gd s1 c s2 -> Pc s1 c s2 ->
  sem_pexpr gd s2 e = ok (Vbool false) ->
  Pi_r s1 (Cwhile c e c') s2.
Proof.
  move=> _ Hc H vm1 Hvm1.
  have [vm2 [Hs2 Hvm2]] := Hc _ Hvm1.
  have [v' [H1 /value_uincl_bool1 ?]]:= sem_pexpr_uincl Hvm2 H;subst.
  by exists vm2;split=> //;apply: Ewhile_false=> //;rewrite H1.
Qed.

Local Lemma Hfor s1 s2 (i : var_i) d lo hi c (vlo vhi : Z) :
  sem_pexpr gd s1 lo = ok (Vint vlo) ->
  sem_pexpr gd s1 hi = ok (Vint vhi) ->
  sem_for p gd i (wrange d vlo vhi) s1 c s2 ->
  Pfor i (wrange d vlo vhi) s1 c s2 ->
  Pi_r s1 (Cfor i (d, lo, hi) c) s2.
Proof.
  move=> H H' _ Hfor vm1 Hvm1. 
  have [? [H1 /value_uincl_int1 ?]]:= sem_pexpr_uincl Hvm1 H;subst.
  have [? [H3 /value_uincl_int1 ?]]:= sem_pexpr_uincl Hvm1 H';subst.
  have [vm2 []??]:= Hfor _ Hvm1; exists vm2;split=>//.
  by econstructor;eauto;rewrite ?H1 ?H3.
Qed.

Local Lemma Hfor_nil s i c : Pfor i [::] s c s.
Proof. by move=> vm1 Hvm1;exists vm1;split=> //;constructor. Qed.

Local Lemma Hfor_cons s1 s1' s2 s3 (i : var_i) (w : Z) (ws : seq Z) c :
  write_var i w s1 = ok s1' ->
  sem p gd s1' c s2 -> Pc s1' c s2 ->
  sem_for p gd i ws s2 c s3 -> Pfor i ws s2 c s3 -> Pfor i (w :: ws) s1 c s3.
Proof.
  move=> Hi _ Hc _ Hf vm1 Hvm1.
  have [vm1' [Hi' /Hc]] := write_var_uincl Hvm1 (value_uincl_refl _) Hi.
  move=> [vm2 [Hsc /Hf]] [vm3 [Hsf Hvm3]];exists vm3;split => //.
  by econstructor;eauto.
Qed.

Local Lemma Hcall s1 m2 s2 ii xs fn args vargs vs :
  sem_pexprs gd s1 args = ok vargs ->
  sem_call p gd (emem s1) fn vargs m2 vs ->
  Pfun (emem s1) fn vargs m2 vs ->
  write_lvals gd {| emem := m2; evm := evm s1 |} xs vs = ok s2 ->
  Pi_r s1 (Ccall ii xs fn args) s2.
Proof.
  move=> Hargs Hcall Hfd Hxs vm1 Hvm1.
  have [vargs' [Hsa /Hfd [vs' [Hc Hvres]]]]:= sem_pexprs_uincl Hvm1 Hargs.
  have Hvm1' : vm_uincl (evm {| emem := m2; evm := evm s1 |}) vm1 by done.
  have [vm2' [??]] := writes_uincl Hvm1' Hvres Hxs.
  exists vm2';split=>//.
  econstructor;eauto.
Qed.

Lemma check_ty_val_uincl v1 x v2 : 
  check_ty_val x v1 → value_uincl v1 v2 → check_ty_val x v2.
Proof.
  rewrite /check_ty_val => h /value_uincl_subtype.
  by apply: subtype_trans.
Qed.

Lemma all2_check_ty_val v1 x v2 : 
  all2 check_ty_val x v1 → List.Forall2 value_uincl v1 v2 → all2 check_ty_val x v2.
Proof.
  move=> /all2P H1 H2;apply /all2P;apply: Forall2_trans H1 H2;apply check_ty_val_uincl.
Qed.
   
Local Lemma Hproc m1 m2 fn fd vargs s1 vm2 vres:
  get_fundef p fn = Some fd ->
  all2 check_ty_val fd.(f_tyin) vargs ->
  write_vars (f_params fd) vargs {| emem := m1; evm := vmap0 |} = ok s1 ->
  sem p gd s1 (f_body fd) {| emem := m2; evm := vm2 |} ->
  Pc s1 (f_body fd) {| emem := m2; evm := vm2 |} ->
  mapM (fun x : var_i => get_var vm2 x) (f_res fd) = ok vres ->
  all2 check_ty_val fd.(f_tyout) vres ->
  Pfun m1 fn vargs m2 vres.
Proof.
  move=> Hget Hca Hargs Hsem Hrec Hmap Hcr vargs' Uargs.
  have [vm1 [Hargs' Hvm1]] := write_vars_uincl (vm_uincl_refl _) Uargs Hargs.
  have [vm2' /= [] Hsem' Uvm2]:= Hrec _ Hvm1.
  have [vs2 [Hvs2 Hsub]] := get_vars_uincl Uvm2 Hmap.
  exists vs2;split=>//.
  econstructor;eauto.
  apply: all2_check_ty_val Hca Uargs.
  apply: all2_check_ty_val Hcr Hsub.
Qed.

Lemma sem_call_uincl vargs m1 f m2 vres vargs':
  List.Forall2 value_uincl vargs vargs' ->
  sem_call p gd m1 f vargs m2 vres ->
  exists vres', sem_call p gd m1 f vargs' m2 vres' /\ List.Forall2 value_uincl vres vres'.
Proof.
  move=> H1 H2.
  by apply:
    (@sem_call_Ind p gd Pc Pi_r Pi Pfor Pfun Hnil Hcons HmkI Hasgn Hopn
        Hif_true Hif_false Hwhile_true Hwhile_false Hfor Hfor_nil Hfor_cons Hcall Hproc) H1.
Qed.

Lemma sem_i_uincl s1 i s2 vm1 :
  vm_uincl (evm s1) vm1 ->
  sem_i p gd s1 i s2 ->
  exists vm2,
    sem_i p gd {|emem := emem s1; evm := vm1|} i {|emem := emem s2; evm := vm2|} /\
    vm_uincl (evm s2) vm2.
Proof.
  move=> H1 H2.
  by apply:
    (@sem_i_Ind p gd Pc Pi_r Pi Pfor Pfun Hnil Hcons HmkI Hasgn Hopn
        Hif_true Hif_false Hwhile_true Hwhile_false Hfor Hfor_nil Hfor_cons Hcall Hproc) H1.
Qed.

Lemma sem_I_uincl s1 i s2 vm1 :
  vm_uincl (evm s1) vm1 ->
  sem_I p gd s1 i s2 ->
  exists vm2,
    sem_I p gd {|emem := emem s1; evm := vm1|} i {|emem := emem s2; evm := vm2|} /\
    vm_uincl (evm s2) vm2.
Proof.
  move=> H1 H2.
  by apply:
    (@sem_I_Ind p gd Pc Pi_r Pi Pfor Pfun Hnil Hcons HmkI Hasgn Hopn
        Hif_true Hif_false Hwhile_true Hwhile_false Hfor Hfor_nil Hfor_cons Hcall Hproc) H1.
Qed.

Lemma sem_uincl s1 c s2 vm1 :
  vm_uincl (evm s1) vm1 ->
  sem p gd s1 c s2 ->
  exists vm2,
    sem p gd {|emem := emem s1; evm := vm1|} c {|emem := emem s2; evm := vm2|} /\
    vm_uincl (evm s2) vm2.
Proof.
  move=> H1 H2.
  by apply:
    (@sem_Ind p gd Pc Pi_r Pi Pfor Pfun Hnil Hcons HmkI Hasgn Hopn
        Hif_true Hif_false Hwhile_true Hwhile_false Hfor Hfor_nil Hfor_cons Hcall Hproc) H1.
Qed.

End UNDEFINCL.

Lemma eq_exprP gd s e1 e2 : eq_expr e1 e2 -> sem_pexpr gd s e1 = sem_pexpr gd s e2.
Proof.
  elim: e1 e2=> [z  | b  | sz e He | x | g | x e He | sz x e He | o e  He | o e1 He1 e2 He2 | e He e1 He1 e2 He2]
                [z' | b' | sz' e'   | x' | g' | x' e'  | sz' x' e'  | o' e' | o' e1' e2' | e' e1' e2'] //=.
  + by move=> /eqP ->.   + by move=> /eqP ->.
  + by move=> /andP [] /eqP -> /He ->.
  + by move=> /eqP ->.
  + by move=> /eqP ->.
  + by move=> /andP [] /eqP -> /He ->.
  + by case/andP => /andP [] /eqP -> /eqP -> /He ->.
  + by move=> /andP[]/eqP -> /He ->.
  + by move=> /andP[]/andP[] /eqP -> /He1 -> /He2 ->.
  by move=> /andP[]/andP[] /He -> /He1 -> /He2 ->.
Qed.

Lemma eq_exprsP gd m es1 es2:
  all2 eq_expr es1 es2 → sem_pexprs gd m es1 = sem_pexprs gd m es2.
Proof.
 rewrite /sem_pexprs.
 by elim: es1 es2 => [ | ?? Hrec] [ | ??] //= /andP [] /eq_exprP -> /Hrec ->.
Qed.

Lemma eq_lvalP gd m lv lv' v :
  eq_lval lv lv' ->
  write_lval gd lv v m = write_lval gd lv' v m.
Proof.
  case: lv lv'=> [ ?? | [??] | sz [??] e | [??] e] [ ?? | [??] | sz' [??] e' | [??] e'] //=.
  + by move=> /eqP ->.
  + by move=> /eqP ->.
  + by case/andP => /andP [] /eqP -> /eqP -> /eq_exprP ->.
  by move=> /andP [/eqP -> /eq_exprP ->].
Qed.

Lemma eq_lvalsP gd m ls1 ls2 vs:
  all2 eq_lval ls1 ls2 → write_lvals gd m ls1 vs =  write_lvals gd m ls2 vs.
Proof.
 rewrite /write_lvals.
 elim: ls1 ls2 vs m => [ | l1 ls1 Hrec] [ | l2 ls2] //= [] // v vs m.
 by move=> /andP [] /eq_lvalP -> /Hrec; case: write_lval => /=.
Qed.

Lemma ok_inj E A (x y:A) : @Ok E A x = @Ok E A y -> x = y.
Proof. by move=> []. Qed.

Lemma to_val_inj t (v1 v2:sem_t t) : to_val v1 = to_val v2 -> v1 = v2.
Proof.
  by case: t v1 v2 => //= [ | | sz p | sz ] v1 v2 => [ []|[] |/Varr_inj1 |[] ] ->.
Qed.

Lemma pto_val_inj t (v1 v2:psem_t t) : pto_val v1 = pto_val v2 -> v1 = v2.
Proof.
  case: t v1 v2 => //= [ | | sz p | sz ] v1 v2 => [ []|[] | /Varr_inj1 | ] //.
  case: v1 v2 => sz1 w1 p1 [sz2 w2 p2] /=.  
  move=> /Vword_inj [e];subst => /= <-.
  by rewrite (@eq_irrelevance _ _ _ p1 p2).
Qed.

Lemma to_val_undef  t (v:sem_t t) : to_val v <> Vundef t.
Proof. by case: t v. Qed.

Lemma pto_val_undef  t (v:psem_t t) : pto_val v <> Vundef t.
Proof. by case: t v. Qed.

Lemma vmap_eqP (lv1 lv2 : vmap) :
  (lv1 = lv2) <-> (forall x, get_var lv1 x = get_var lv2 x).
Proof.
   split => [-> // | Hget];apply Fv.map_ext => x.
   have := Hget x;rewrite /get_var /on_vu.
   case: (lv1.[x])%vmap (lv2.[x])%vmap => [ v1 | []] [v2 | []] //.
   + by move=> H; have -> := pto_val_inj (ok_inj H).
   + by move=> H;have {H} /pto_val_undef:= ok_inj H.
   by move=> H; have {H}  /pto_val_undef := ok_inj (Logic.eq_sym H). 
Qed.

(* TODO: move *)
Lemma to_word_to_pword s v w: to_word s v = ok w -> to_pword s v = ok (pword_of_word w).
Proof.
  case: v => //= [ s' w'| []//?];last by case: ifP.
  move=> /truncate_wordP [hle] ?;subst w.
  case: Sumbool.sumbool_of_bool => /=.
  + move=> e;move: (e);rewrite cmp_le_eq_lt in e => e'.
    case /orP: e => [hlt | /eqP ?];first by rewrite -cmp_nlt_le hlt in hle.
    by subst; rewrite /pword_of_word zero_extend_u;do 2 f_equal;apply eq_irrelevance.
  by move=> /negbT;rewrite cmp_nle_lt /truncate_word => h;rewrite (cmp_lt_le h) /=.
Qed.
