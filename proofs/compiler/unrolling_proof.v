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

(* * Prove properties about semantics of dmasm input language *)

(* ** Imports and settings *)
From mathcomp Require Import all_ssreflect.
Require Import ZArith sem compiler_util.
Require Export unrolling.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Local Open Scope vmap_scope.
Local Open Scope seq_scope.

Section PROOF.

  Variable p : prog.
  Context (gd: glob_defs).

  Definition p' := unroll_prog p.

  Let Pi_r (s:estate) (i:instr_r) (s':estate) :=
    forall ii, sem p' gd s (unroll_i (MkI ii i)) s'.

  Let Pi (s:estate) (i:instr) (s':estate) :=
    sem p' gd s (unroll_i i) s'.

  Let Pc (s:estate) (c:cmd) (s':estate) :=
    sem p' gd s (unroll_cmd unroll_i c) s'.

  Let Pfor (i:var_i) vs s c s' :=
    sem_for p' gd i vs s (unroll_cmd unroll_i c) s'
    /\ forall ii, sem p' gd s
      (flatten (map (fun n => assgn ii i (Pconst n) :: (unroll_cmd unroll_i c)) vs)) s'.

  Let Pfun m1 fn vargs m2 vres :=
    sem_call p' gd m1 fn vargs m2 vres.

  Local Lemma Hskip s : Pc s [::] s.
  Proof. exact: Eskip. Qed.

  Local Lemma Hcons s1 s2 s3 i c :
    sem_I p gd s1 i s2 ->
    Pi s1 i s2 -> sem p gd s2 c s3 -> Pc s2 c s3 -> Pc s1 (i :: c) s3.
  Proof.
    move=> Hsi Hi Hsc Hc.
    exact: (sem_app Hi Hc).
  Qed.

  Local Lemma HmkI ii i s1 s2 :
    sem_i p gd s1 i s2 -> Pi_r s1 i s2 -> Pi s1 (MkI ii i) s2.
  Proof. move=> _ Hi; exact: Hi. Qed.

  Local Lemma Hassgn s1 s2 x tag e :
    Let v := sem_pexpr gd s1 e in write_lval gd x v s1 = Ok error s2 ->
    Pi_r s1 (Cassgn x tag e) s2.
  Proof.
    move=> Hw ii.
    by apply: sem_seq1; apply: EmkI; apply: Eassgn.
  Qed.

  Local Lemma Hopn s1 s2 t o xs es :
    sem_sopn gd o s1 xs es = ok s2 ->
    Pi_r s1 (Copn xs t o es) s2.
  Proof.
    move=> Hw ii.
    by apply: sem_seq1; apply: EmkI; apply: Eopn.
  Qed.

  Local Lemma Hif_true s1 s2 e c1 c2 :
    Let x := sem_pexpr gd s1 e in to_bool x = Ok error true ->
    sem p gd s1 c1 s2 -> Pc s1 c1 s2 -> Pi_r s1 (Cif e c1 c2) s2.
  Proof.
    move=> Hb Hsc Hc ii.
    by apply: sem_seq1; apply: EmkI; apply: Eif_true.
  Qed.

  Local Lemma Hif_false s1 s2 e c1 c2 :
    Let x := sem_pexpr gd s1 e in to_bool x = Ok error false ->
    sem p gd s1 c2 s2 -> Pc s1 c2 s2 -> Pi_r s1 (Cif e c1 c2) s2.
  Proof.
    move=> Hb Hsc Hc ii.
    by apply: sem_seq1; apply: EmkI; apply: Eif_false.
  Qed.

  Local Lemma Hwhile_true s1 s2 s3 s4 c e c' :
    sem p gd s1 c s2 -> Pc s1 c s2 ->
    Let x := sem_pexpr gd s2 e in to_bool x = ok true ->
    sem p gd s2 c' s3 -> Pc s2 c' s3 ->
    sem_i p gd s3 (Cwhile c e c') s4 -> Pi_r s3 (Cwhile c e c') s4 -> Pi_r s1 (Cwhile c e c') s4.
  Proof.
    move=> Hsc Hc Hb Hsc' Hc' Hsi Hi ii.
    apply: sem_seq1; apply: EmkI; apply: Ewhile_true=> //; eauto=> /=.
    move: Hi=> /(_ ii) Hi.
    sinversion Hi.
    sinversion H2.
    sinversion H4.
    apply: H5.
  Qed.

  Local Lemma Hwhile_false s1 s2 c e c' :
    sem p gd s1 c s2 -> Pc s1 c s2 ->
    Let x := sem_pexpr gd s2 e in to_bool x = ok false ->
    Pi_r s1 (Cwhile c e c') s2.
  Proof.
   move=> Hsc Hc Hb ii.
   by apply: sem_seq1; apply: EmkI; apply: Ewhile_false.
  Qed.

  Local Lemma Hfor s1 s2 (i:var_i) d lo hi c vlo vhi :
    Let x := sem_pexpr gd s1 lo in to_int x = Ok error vlo ->
    Let x := sem_pexpr gd s1 hi in to_int x = Ok error vhi ->
    sem_for p gd i (wrange d vlo vhi) s1 c s2 ->
    Pfor i (wrange d vlo vhi) s1 c s2 -> Pi_r s1 (Cfor i (d, lo, hi) c) s2.
  Proof.
    move=> Hlo Hhi Hc [Hfor Hfor'] ii.
    rewrite /=.
    case Hlo': (is_const lo)=> [nlo|].
    + case Hhi': (is_const hi)=> [nhi|].
      + have ->: nlo = vlo.
          rewrite /is_const /= in Hlo'.
          by case: lo Hlo Hlo'=> //= z [] -> [] ->.
        have ->: nhi = vhi.
          rewrite /is_const /= in Hhi'.
          by case: hi Hhi Hhi'=> //= z [] -> [] ->.
        exact: Hfor'.
      apply: sem_seq1; apply: EmkI; apply: Efor; [apply: Hlo|apply: Hhi|apply: Hfor].
    apply: sem_seq1; apply: EmkI; apply: Efor; [apply: Hlo|apply: Hhi|apply: Hfor].
  Qed.

  Local Lemma Hfor_nil s i c: Pfor i [::] s c s.
  Proof.
    split=> //=.
    exact: EForDone.
    move=> ii.
    apply: Eskip.
  Qed.

  Local Lemma Hfor_cons s1 s1' s2 s3 (i : var_i) (w:Z) (ws:seq Z) c :
    write_var i w s1 = Ok error s1' ->
    sem p gd s1' c s2 ->
    Pc s1' c s2 ->
    sem_for p gd i ws s2 c s3 -> Pfor i ws s2 c s3 -> Pfor i (w :: ws) s1 c s3.
  Proof.
    move=> Hw Hsc Hc Hsfor [Hfor Hfor']; split=> [|ii].
    apply: EForOne; [exact: Hw|exact: Hc|exact: Hfor].
    move: Hfor'=> /(_ ii) Hfor'.
    apply: Eseq; [apply: EmkI; apply: Eassgn; exact: Hw|apply: sem_app].
    exact: Hc.
    exact: Hfor'.
  Qed.

  Local Lemma Hcall s1 m2 s2 ii xs fn args vargs vs:
    sem_pexprs gd s1 args = Ok error vargs ->
    sem_call p gd (emem s1) fn vargs m2 vs ->
    Pfun (emem s1) fn vargs m2 vs ->
    write_lvals gd {| emem := m2; evm := evm s1 |} xs vs = Ok error s2 ->
    Pi_r s1 (Ccall ii xs fn args) s2.
  Proof.
    move=> Hexpr Hcall Hfun Hw ii'.
    apply: sem_seq1; apply: EmkI; apply: Ecall; [exact: Hexpr|exact: Hfun|exact: Hw].
  Qed.

  Local Lemma Hproc m1 m2 fn f vargs s1 vm2 vres:
    get_fundef p fn = Some f ->
    write_vars (f_params f) vargs {| emem := m1; evm := vmap0 |} = ok s1 ->
    sem p gd s1 (f_body f) {| emem := m2; evm := vm2 |} ->
    Pc s1 (f_body f) {| emem := m2; evm := vm2 |} ->
    mapM (fun x : var_i => get_var vm2 x) (f_res f) = ok vres ->
    List.Forall is_full_array vres ->
    Pfun m1 fn vargs m2 vres.
  Proof.
    case: f=> fi fparams fc fres /= Hget Hw _ Hc Hres Hfull.
    apply: EcallRun=> //.
    by rewrite get_map_prog Hget.
    exact: Hw.
    exact: Hc.
    exact: Hres.
  Qed.

  Lemma unroll_callP f mem mem' va vr:
    sem_call p gd mem f va mem' vr ->
    sem_call p' gd mem f va mem' vr.
  Proof.
    apply (@sem_call_Ind p gd Pc Pi_r Pi Pfor Pfun Hskip Hcons HmkI Hassgn Hopn
             Hif_true Hif_false Hwhile_true Hwhile_false Hfor Hfor_nil Hfor_cons Hcall Hproc).
  Qed.

End PROOF.
