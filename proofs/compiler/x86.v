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

(* -------------------------------------------------------------------- *)
From mathcomp Require Import all_ssreflect.
(* ------- *) Require Import xseq expr linear compiler_util.
(* ------- *) Require Import low_memory x86_sem.

Import Ascii.
Import Relations.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

(* -------------------------------------------------------------------- *)
Definition string_of_register r :=
  match r with
  | RAX => "RAX"
  | RCX => "RCX"
  | RDX => "RDX"
  | RBX => "RBX"
  | RSP => "RSP"
  | RBP => "RBP"
  | RSI => "RSI"
  | RDI => "RDI"
  | R8  => "R8"
  | R9  => "R9"
  | R10 => "R10"
  | R11 => "R11"
  | R12 => "R12"
  | R13 => "R13"
  | R14 => "R14"
  | R15 => "R15"
  end%string.

Definition string_of_rflag (rf : rflag) : string :=
  match rf with
 | CF => "CF"
 | PF => "PF"
 | ZF => "ZF"
 | SF => "SF"
 | OF => "OF"
 | DF => "DF"
 end%string.

(* -------------------------------------------------------------------- *)
Definition regs_strings :=
  Eval compute in [seq (string_of_register x, x) | x <- registers].

Lemma regs_stringsE : regs_strings =
  [seq (string_of_register x, x) | x <- registers].
Proof. by []. Qed.

(* -------------------------------------------------------------------- *)
Definition rflags_strings :=
  Eval compute in [seq (string_of_rflag x, x) | x <- rflags].

Lemma rflags_stringsE : rflags_strings =
  [seq (string_of_rflag x, x) | x <- rflags].
Proof. by []. Qed.

(* -------------------------------------------------------------------- *)
Definition reg_of_string (s : string) :=
  assoc regs_strings s.

(* -------------------------------------------------------------------- *)
Definition rflag_of_string (s : string) :=
  assoc rflags_strings s.

(* -------------------------------------------------------------------- *)
Lemma rflag_of_stringK : pcancel string_of_rflag rflag_of_string.
Proof. by case. Qed.

Lemma reg_of_stringK : pcancel string_of_register reg_of_string.
Proof. by case. Qed.

Lemma inj_string_of_rflag : injective string_of_rflag.
Proof. by apply: (pcan_inj rflag_of_stringK). Qed.

Lemma inj_string_of_register : injective string_of_register.
Proof. by apply: (pcan_inj reg_of_stringK). Qed.

(* -------------------------------------------------------------------- *)
Lemma inj_reg_of_string s1 s2 r :
     reg_of_string s1 = Some r
  -> reg_of_string s2 = Some r
  -> s1 = s2.
Proof. by rewrite /reg_of_string !regs_stringsE; apply: inj_assoc. Qed.

(* -------------------------------------------------------------------- *)
Lemma inj_rflag_of_string s1 s2 rf :
     rflag_of_string s1 = Some rf
  -> rflag_of_string s2 = Some rf
  -> s1 = s2.
Proof. by rewrite /rflag_of_string !rflags_stringsE; apply: inj_assoc. Qed.

(* -------------------------------------------------------------------- *)
Record xfundef := XFundef {
 xfd_stk_size : Z;
 xfd_nstk : register;
 xfd_arg  : seq register;
 xfd_body : seq asm;
 xfd_res  : seq register;
}.

Definition xprog := seq (funname * xfundef).

(* ** Conversion to assembly *
 * -------------------------------------------------------------------- *)

Definition invalid_rflag (s: string) : asm_error :=
  AsmErr_string ("Invalid rflag name: " ++ s).

Definition invalid_register (s: string) : asm_error :=
  AsmErr_string ("Invalid register name: " ++ s).

Global Opaque invalid_rflag invalid_register.

(* -------------------------------------------------------------------- *)
Definition rflag_of_var ii (v: var) :=
  match v with
  | Var sbool s =>
     match (rflag_of_string s) with
     | Some r => ciok r
     | None => cierror ii (Cerr_assembler (invalid_rflag s))
     end
  | _ => cierror ii (Cerr_assembler (AsmErr_string "Invalid rflag type"))
  end.

(* -------------------------------------------------------------------- *)
Definition reg_of_var ii (v: var) :=
  match v with
  | Var sword s =>
     match (reg_of_string s) with
     | Some r => ciok r
     | None => cierror ii (Cerr_assembler (invalid_register s))
     end
  | _ => cierror ii (Cerr_assembler (AsmErr_string "Invalid register type"))
  end.

(* -------------------------------------------------------------------- *)
Definition reg_of_vars ii (vs: seq var_i) :=
  mapM (reg_of_var ii \o v_var) vs.

(* -------------------------------------------------------------------- *)
Definition word_of_int (z: Z) := ciok (I64.repr z).

(* -------------------------------------------------------------------- *)
Definition word_of_pexpr ii e :=
  match e with
  | Pcast (Pconst z) => word_of_int z
  | _ => cierror ii (Cerr_assembler (AsmErr_string "Invalid integer constant"))
  end.

(* -------------------------------------------------------------------- *)
Definition oprd_of_lval ii (l: lval) :=
  match l with
  | Lnone _ _ =>
     cierror ii (Cerr_assembler (AsmErr_string "Lnone not implemented"))
  | Lvar v =>
     Let s := reg_of_var ii v in
     ciok (Reg_op s)
  | Lmem v e =>
     Let s := reg_of_var ii v in
     Let w := word_of_pexpr ii e in
     ciok (Adr_op (mkAddress w (Some s) Scale1 None))
  | Laset v e =>
     cierror ii (Cerr_assembler (AsmErr_string "Laset not handled in assembler"))
  end.

(* -------------------------------------------------------------------- *)
Definition scale_of_z ii z :=
  match z with
  | 1 => ok Scale1
  | 2 => ok Scale2
  | 4 => ok Scale4
  | 8 => ok Scale8
  | _ => cierror ii (Cerr_assembler (AsmErr_string "invalid scale"))
  end%Z.

(* s + e :
   s + n
   s + x
   s + y + n
   s + sc * y
   s + sc * y + n *)

Variant ofs := 
  | Ofs_const of Z
  | Ofs_var   of var_i
  | Ofs_mul   of Z & var_i
  | Ofs_add   of Z & var_i & Z
  | Ofs_error.
  
(* -------------------------------------------------------------------- *)
Fixpoint addr_ofs e := 
  match e with
  | Pcast (Pconst z) => Ofs_const z
  | Pvar  x          => Ofs_var x
  | Papp2 (Omul Op_w) e1 e2 =>
    match addr_ofs e1, addr_ofs e2 with
    | Ofs_const n1, Ofs_const n2 => Ofs_const (n1 * n2)%Z
    | Ofs_const sc, Ofs_var   x  => Ofs_mul sc x 
    | Ofs_var   x , Ofs_const sc => Ofs_mul sc x      
    | _           , _            => Ofs_error
    end
  | Papp2 (Oadd Op_w) e1 e2 =>
    match addr_ofs e1, addr_ofs e2 with
    | Ofs_const n1, Ofs_const n2 => Ofs_const (n1 + n2)%Z
    | Ofs_const n , Ofs_var   x  => Ofs_add 1%Z x n
    | Ofs_var   x , Ofs_const n  => Ofs_add 1%Z x n
    | Ofs_mul sc x, Ofs_const n  => Ofs_add sc  x n
    | Ofs_const n , Ofs_mul sc x => Ofs_add sc  x n
    | _           , _            => Ofs_error
    end
  | _ => Ofs_error
  end.

(* -------------------------------------------------------------------- *)
Definition addr_of_pexpr ii s (e: pexpr) :=
  match addr_ofs e with
  | Ofs_const z => 
    Let n := word_of_int z in
    ciok (mkAddress n (Some s) Scale1 None)
  | Ofs_var x =>
    Let x := reg_of_var ii x in
    ciok (mkAddress I64.zero (Some s) Scale1 (Some x))
  | Ofs_mul sc x =>
    Let x := reg_of_var ii x in
    Let sc := scale_of_z ii sc in
    ciok (mkAddress I64.zero (Some s) sc (Some x))
  | Ofs_add sc x z =>
    Let x := reg_of_var ii x in
    Let n := word_of_int z in
    Let sc := scale_of_z ii sc in
    ciok (mkAddress n (Some s) sc (Some x))
  | Ofs_error =>
    cierror ii (Cerr_assembler (AsmErr_string "Invalid address expression"))
  end.

(* -------------------------------------------------------------------- *)
Definition oprd_of_pexpr ii (e: pexpr) :=
  match e with
  | Pcast (Pconst z) =>
     Let w := word_of_int z in
     ciok (Imm_op w)
  | Pvar v =>
     Let s := reg_of_var ii v in
     ciok (Reg_op s)
  | Pglobal g =>
    ciok (Glo_op g)
  | Pload v e => (* FIXME: can we recognize more expression for e ? *)
     Let s := reg_of_var ii v in
     Let w := addr_of_pexpr ii s e in
     ciok (Adr_op w)
  | _ => cierror ii (Cerr_assembler (AsmErr_string "Invalid pexpr for oprd"))
  end.

(* -------------------------------------------------------------------- *)
Definition ireg_of_pexpr ii (e: pexpr) :=
  match e with
  | Pcast (Pconst z) =>
     Let w := word_of_int z in
     ciok (Imm_ir w)
  | Pvar v =>
     Let s := reg_of_var ii v in
     ciok (Reg_ir s)
  | _ => cierror ii (Cerr_assembler (AsmErr_string "Invalid pexpr for ireg"))
  end.

(* -------------------------------------------------------------------- *)
Definition oreg_of_pexpr ii e := 
  match e with 
  | Pcast (Pconst z) => 
    if z == 0%Z then ciok None 
    else cierror ii (Cerr_assembler (AsmErr_string "Invalid pexpr for oreg"))
  | Pvar v           => Let r := reg_of_var ii v in ciok (Some r)
  | _                => cierror ii (Cerr_assembler (AsmErr_string "Invalid pexpr for oreg")) 
  end.

(* -------------------------------------------------------------------- *)
Definition assemble_cond ii (e: pexpr) : ciexec condt :=
  match e with
  | Pvar v =>
    Let r := rflag_of_var ii v in
    match r with
    | OF => ok O_ct
    | CF => ok B_ct
    | ZF => ok E_ct
    | SF => ok S_ct
    | PF => ok P_ct
    | DF => cierror ii (Cerr_assembler (AsmErr_string "Cannot branch on DF"))
    end

  | Papp1 Onot (Pvar v) =>
    Let r := rflag_of_var ii v in
    match r with
    | OF => ok NO_ct
    | CF => ok NB_ct
    | ZF => ok NE_ct
    | SF => ok NS_ct
    | PF => ok NP_ct
    | DF => cierror ii (Cerr_assembler (AsmErr_string "Cannot branch on ~~ DF"))
    end

  | Papp2 Oor (Pvar vcf) (Pvar vzf) =>
    Let rcf := rflag_of_var ii vcf in
    Let rzf := rflag_of_var ii vzf in
    if ((rcf == CF) && (rzf == ZF)) then
      ok BE_ct
    else cierror ii (Cerr_assembler (AsmErr_string "Invalid condition (BE)"))

  | Papp2 Oand (Papp1 Onot (Pvar vcf)) (Papp1 Onot (Pvar vzf)) =>
    Let rcf := rflag_of_var ii vcf in
    Let rzf := rflag_of_var ii vzf in
    if ((rcf == CF) && (rzf == ZF)) then
      ok NBE_ct
    else cierror ii (Cerr_assembler (AsmErr_string "Invalid condition (NBE)"))

  | Pif (Pvar vsf) (Papp1 Onot (Pvar vof1)) (Pvar vof2) =>
    Let rsf := rflag_of_var ii vsf in
    Let rof1 := rflag_of_var ii vof1 in
    Let rof2 := rflag_of_var ii vof2 in
    if ((rsf == SF) && (rof1 == OF) && (rof2 == OF)) then
      ok L_ct
    else cierror ii (Cerr_assembler (AsmErr_string "Invalid condition (L)"))

  | Pif (Pvar vsf) (Pvar vof1) (Papp1 Onot (Pvar vof2)) =>
    Let rsf := rflag_of_var ii vsf in
    Let rof1 := rflag_of_var ii vof1 in
    Let rof2 := rflag_of_var ii vof2 in
    if ((rsf == SF) && (rof1 == OF) && (rof2 == OF)) then
      ok NL_ct
    else cierror ii (Cerr_assembler (AsmErr_string "Invalid condition (NL)"))

  | Papp2 Oor (Pvar vzf)
          (Pif (Pvar vsf) (Papp1 Onot (Pvar vof1)) (Pvar vof2)) =>
    Let rzf := rflag_of_var ii vzf in
    Let rsf := rflag_of_var ii vsf in
    Let rof1 := rflag_of_var ii vof1 in
    Let rof2 := rflag_of_var ii vof2 in
    if ((rzf == ZF) && (rsf == SF) && (rof1 == OF) && (rof2 == OF)) then
      ok LE_ct
    else cierror ii (Cerr_assembler (AsmErr_string "Invalid condition (LE)"))

  | Papp2 Oand
             (Papp1 Onot (Pvar vzf))
             (Pif (Pvar vsf) (Pvar vof1) (Papp1 Onot (Pvar vof2))) =>
    Let rzf := rflag_of_var ii vzf in
    Let rsf := rflag_of_var ii vsf in
    Let rof1 := rflag_of_var ii vof1 in
    Let rof2 := rflag_of_var ii vof2 in
    if ((rzf == ZF) && (rsf == SF) && (rof1 == OF) && (rof2 == OF)) then
      ok NLE_ct
    else cierror ii (Cerr_assembler (AsmErr_string "Invalid condition (NLE)"))

  | _ => cierror ii (Cerr_assembler (AsmErr_cond e))
  end.

(* -------------------------------------------------------------------- *)
Variant binuop :=
  | BU_ADD
  | BU_SUB
  | BU_AND
  | BU_OR
  | BU_XOR.

Variant bincop :=
  | BC_ADC
  | BC_SBB.

Variant shtop2 :=
  | ST_SHL
  | ST_SHR
  | ST_SAR.

Variant shtop := 
  | ST_OP2 of shtop2
  | ST_SHLD.

Variant alukind :=
  | LK_CMP
  | LK_BINU of binuop
  | LK_BINC of bincop
  | LK_SHT  of shtop
  | LK_MUL
  | LK_IMUL
  | LK_NEG
  | LK_SET0.

Variant opkind :=
  | OK_ALU of alukind
  | OK_CNT of bool
  | OK_MOV
  | OK_MOVcc
  | OK_LEA
  | OK_None.

Definition kind_of_sopn (o : sopn) :=
  match o with
  | Oset0       => OK_ALU LK_SET0
  | Ox86_CMP    => OK_ALU LK_CMP
  | Ox86_ADD    => OK_ALU (LK_BINU BU_ADD)
  | Ox86_ADC    => OK_ALU (LK_BINC BC_ADC)
  | Ox86_SUB    => OK_ALU (LK_BINU BU_SUB)
  | Ox86_SBB    => OK_ALU (LK_BINC BC_SBB)
  | Ox86_NEG    => OK_ALU LK_NEG
  | Ox86_MUL    => OK_ALU LK_MUL
  | Ox86_IMUL64 => OK_ALU LK_IMUL

  | Ox86_SHR    => OK_ALU (LK_SHT (ST_OP2 ST_SHR))
  | Ox86_SHL    => OK_ALU (LK_SHT (ST_OP2 ST_SHL))
  | Ox86_SAR    => OK_ALU (LK_SHT (ST_OP2 ST_SAR))
  | Ox86_SHLD   => OK_ALU (LK_SHT ST_SHLD)
  | Ox86_DEC    => OK_CNT false
  | Ox86_INC    => OK_CNT true
  | Ox86_AND    => OK_ALU (LK_BINU BU_AND)
  | Ox86_OR     => OK_ALU (LK_BINU BU_OR)
  | Ox86_XOR    => OK_ALU (LK_BINU BU_XOR)
  | Ox86_MOV    => OK_MOV
  | Ox86_CMOVcc => OK_MOVcc
  | Ox86_LEA    => OK_LEA
  (* Not Implemented ... *)
  | Ox86_IMUL64imm
  | Ox86_IMUL | Ox86_DIV | Ox86_IDIV | Ox86_SETcc | Ox86_TEST | Ox86_NOT => OK_None
  (* Should not be done *)
  | Omulu | Oaddcarry | Osubcarry => OK_None
  (*  | _           => OK_None *)
  end.

Definition string_of_aluk (o : alukind) :=
  let op :=
      match o with
      | LK_SET0                 => Oset0 
      | LK_CMP                  => Ox86_CMP   
      | LK_BINU BU_ADD          => Ox86_ADD   
      | LK_BINC BC_ADC          => Ox86_ADC   
      | LK_BINU BU_SUB          => Ox86_SUB   
      | LK_BINC BC_SBB          => Ox86_SBB   
      | LK_BINU BU_AND          => Ox86_AND
      | LK_BINU BU_OR           => Ox86_OR
      | LK_BINU BU_XOR          => Ox86_XOR
      | LK_NEG                  => Ox86_NEG   
      | LK_MUL                  => Ox86_MUL   
      | LK_IMUL                 => Ox86_IMUL64
      | LK_SHT (ST_OP2 ST_SHR)  => Ox86_SHR   
      | LK_SHT (ST_OP2 ST_SHL)  => Ox86_SHL   
      | LK_SHT (ST_OP2 ST_SAR)  => Ox86_SAR   
      | LK_SHT ST_SHLD          => Ox86_SHLD   
      end

  in string_of_sopn op.

(* -------------------------------------------------------------------- *)
Variant alu_vars :=
| ALUVars of var_i & var_i & var_i & var_i & var_i.

Definition lvals_as_alu_vars (l : lvals) :=
  match l with
  | [:: Lvar vof, Lvar vcf, Lvar vxf, Lvar vpf, Lvar vzf & l] =>
      Some (ALUVars vof vcf vxf vpf vzf, l)
  | _ => None
  end.

(* -------------------------------------------------------------------- *)
Variant cnt_vars :=
| CNTVars of var_i & var_i & var_i & var_i.

Definition lvals_as_cnt_vars (l : lvals) :=
  match l with
  | [:: Lvar vof; Lvar vsf; Lvar vpf; Lvar vzf; l] =>
      Some (CNTVars vof vsf vpf vzf, l)
  | _ => None
  end.

(* -------------------------------------------------------------------- *)
Section AsN.
Context {T : Type}.

Definition as_unit (s : seq T) :=
  if s is [::] then true else false.

Definition as_singleton (s : seq T) :=
  if s is [:: x] then Some x else None.

Definition as_pair (s : seq T) :=
  if s is [:: x; y] then Some (x, y) else None.

Definition as_triple (s : seq T) :=
  if s is [:: x; y; z] then Some (x, y, z) else None.

Definition as_quadruple (s : seq T) :=
  if s is [:: w; x; y; z] then Some (w, x, y, z) else None.

Lemma as_unitP s : reflect (s = [::]) (as_unit s).
Proof. by case: s => [|x s]; constructor. Qed.

Lemma as_singletonT s x :
  as_singleton s = Some x -> s = [:: x].
Proof. by case: s => [|x' [|]] //= [->]. Qed.

Lemma as_pairT s x y :
  as_pair s = Some (x, y) -> s = [:: x; y].
Proof. by case: s => [|x' [|y' [|]]] //= [-> ->]. Qed.

Lemma as_tripleT s x y z :
  as_triple s = Some (x, y, z) -> s = [:: x; y; z].
Proof. by case: s => [|x' [|y' [|z' [|]]]] //= [-> -> ->]. Qed.

Lemma as_quadrupleT s w x y z :
  as_quadruple s = Some (w, x, y, z) -> s = [:: w; x; y; z].
Proof. by case: s => [|w' [|x' [|y' [|z' [|]]]]] //= [-> -> -> ->]. Qed.

End AsN.

(* -------------------------------------------------------------------- *)
Definition wrong_aluk o : asm_error :=
  AsmErr_string ("wrong arguments / outputs for operator " ++ string_of_aluk o).

Global Opaque wrong_aluk.

(* -------------------------------------------------------------------- *)
Definition assemble_fopn ii (l: lvals) (o: alukind) (e: pexprs) : ciexec asm :=
  match o with
  | LK_CMP =>
    match as_pair e, as_unit l with
    | Some (e1, e2), true =>
      Let o1 := oprd_of_pexpr ii e1 in
      Let o2 := oprd_of_pexpr ii e2 in
      ciok (CMP o1 o2)

    | _, _ =>
      cierror ii (Cerr_assembler (wrong_aluk o))
    end

  | LK_BINU bin =>
    match as_pair e, as_singleton l with
    | Some (e1, e2), Some x =>
      Let o1 := oprd_of_pexpr ii e1 in
      Let o2 := oprd_of_pexpr ii e2 in
      Let ox := oprd_of_lval ii x in

      if (o1 != ox) then
        cierror ii (Cerr_assembler (AsmErr_string
          ("First [rl]val should be the same for " ++ string_of_aluk o)))
      else
        ciok (match bin with
              | BU_ADD => ADD
              | BU_SUB => SUB
              | BU_AND => AND
              | BU_OR  => OR
              | BU_XOR => XOR
              end o1 o2)

    | _, _ =>
      cierror ii (Cerr_assembler (wrong_aluk o))
    end

  | LK_BINC bin =>
    match as_triple e, as_singleton l with
    | Some (e1, e2, Pvar ecf), Some x =>
      Let o1 := oprd_of_pexpr ii e1 in
      Let o2 := oprd_of_pexpr ii e2 in
      Let rcf := rflag_of_var ii ecf in
      Let ox := oprd_of_lval ii x in

      if (rcf != CF) then
        cierror ii (Cerr_assembler
          (AsmErr_string
             ("Carry flag in wrong register for " ++ string_of_aluk o))) else

      if (o1 != ox) then
        cierror ii (Cerr_assembler
          (AsmErr_string
             ("First [rl]val should be the same for " ++ string_of_aluk o))) else

      ciok (match bin with
            | BC_ADC => ADC
            | BC_SBB => SBB
            end o1 o2)

    | _, _ =>
      cierror ii (Cerr_assembler (wrong_aluk o))
    end

  | LK_SHT sht =>
    match e, as_singleton l with
    | e1 :: e2 :: l', Some x =>
      Let o1 := oprd_of_pexpr ii e1 in
      Let o2 := ireg_of_pexpr ii e2 in
      Let ox := oprd_of_lval ii x in
      if (o1 != ox) then
        cierror ii (Cerr_assembler (AsmErr_string
          ("First [rl]val should be the same for " ++ string_of_aluk o)))
      else match sht with
      | ST_OP2 sht =>
        (* FIXME if o2 is a register it should be CL *)
        if l' == [::] then
          ciok (match sht with
                | ST_SHL => SHL
                | ST_SHR => SHR
                | ST_SAR => SAR
                end o1 o2)
        else cierror ii (Cerr_assembler (wrong_aluk o))
      | ST_SHLD =>
        match as_singleton l', o2 with
        | Some e3, Reg_ir r2 => 
           (* FIXME if o3 is a register it should be CL *)
          Let o3 := ireg_of_pexpr ii e3 in
          ciok (SHLD o1 r2 o3)
        | _, _ => cierror ii (Cerr_assembler (wrong_aluk o))
        end
      end
    | _, _ =>
      cierror ii (Cerr_assembler (wrong_aluk o))
    end

  | LK_MUL =>
    match as_pair e, as_pair l with
    | Some (e1, e2), Some (hi, lo) =>
      Let rlo := oprd_of_lval ii lo in
      Let rhi := oprd_of_lval ii hi in
      Let o1  := oprd_of_pexpr ii e1 in
      Let o2  := oprd_of_pexpr ii e2 in
      if (rlo == Reg_op RAX) && (rhi == Reg_op RDX) && (o1 == Reg_op RAX) then
        ok (MUL o2)
      else cierror ii (Cerr_assembler (AsmErr_string ("wrong op/lvals for MUL")))

    | _, _ =>
      cierror ii (Cerr_assembler (wrong_aluk o))
    end

  | LK_IMUL =>
    match as_pair e, as_singleton l with
    | Some (e1, e2), Some x =>
      Let d   := oprd_of_lval ii x in
      Let o1  := oprd_of_pexpr ii e1 in
      match is_wconst e2 with
      | Some c => ok (IMUL d (Some (o1, Some (I64.repr c))))
      | None =>
          Let o2 := oprd_of_pexpr ii e2 in
          if o1 == d then
            ok (IMUL o1 (Some (o2, None)))
          else cierror ii (Cerr_assembler (AsmErr_string ("wrong op/lvals for IMUL")))
      end

    | _, _ =>
      cierror ii (Cerr_assembler (wrong_aluk o))
    end

  | LK_NEG =>
    match as_singleton e, as_singleton l with
    | Some e, Some x =>
      Let d := oprd_of_lval ii x in
      Let o := oprd_of_pexpr ii e in
      if d == o then ok (NEG o) else
        cierror ii (Cerr_assembler
          (AsmErr_string ("src/dst of NEG not identical")))

    | _, _ =>
      cierror ii (Cerr_assembler (wrong_aluk o))
    end
  | LK_SET0 =>
    match e, as_singleton l with
    | [::], Some x =>
      Let d := oprd_of_lval ii x in
      ok (XOR d d)

    | _, _ =>
      cierror ii (Cerr_assembler (wrong_aluk o))
    end
      
  end.

(* -------------------------------------------------------------------- *)
Definition assemble_opn ii (l: lvals) (o: sopn) (e: pexprs) : ciexec asm :=
  match kind_of_sopn o with
  | OK_ALU aluk =>
    match lvals_as_alu_vars l with
    | Some (ALUVars vof vcf vsf vpf vzf, l) =>
      Let rof := rflag_of_var ii vof in
      Let rcf := rflag_of_var ii vcf in
      Let rsf := rflag_of_var ii vsf in
      Let rpf := rflag_of_var ii vpf in
      Let rzf := rflag_of_var ii vzf in
      if ((rof == OF) && (rcf == CF) && (rsf == SF) && (rpf == PF) && (rzf == ZF))
      then assemble_fopn ii l aluk e
      else cierror ii (Cerr_assembler (AsmErr_string "Invalid registers in lvals"))

    | None =>
        cierror ii (Cerr_assembler (AsmErr_string "Invalid number of lvals"))
    end

  | OK_CNT inc =>
    match lvals_as_cnt_vars l with
    | Some (CNTVars vof vsf vpf vzf, l) =>
      Let ol := oprd_of_lval ii l in
      Let rof := rflag_of_var ii vof in
      Let rsf := rflag_of_var ii vsf in
      Let rpf := rflag_of_var ii vpf in
      Let rzf := rflag_of_var ii vzf in
      if ((rof == OF) && (rsf == SF) && (rpf == PF) && (rzf == ZF)) then
      match as_singleton e with
      | Some e =>
        Let or := oprd_of_pexpr ii e in
        if (or == ol) then
          ciok ((if inc then INC else DEC) or)
        else
          cierror ii (Cerr_assembler
            (AsmErr_string "lval & rval of Ox86_DEC/INC should be the same"))
      | _ => cierror ii (Cerr_assembler
            (AsmErr_string "Invalid number of pexpr in Ox86_DEC/INC"))
      end else
        cierror ii (Cerr_assembler (AsmErr_string "Invalid registers in lvals"))
    | _ =>
      cierror ii (Cerr_assembler
        (AsmErr_string "Invalid number of lval in Ox86_DEC/INC"))
    end

  | OK_MOV =>
    match as_singleton l, as_singleton e with
    | Some l, Some e =>
      Let ol := oprd_of_lval ii l in
      Let or := oprd_of_pexpr ii e in
      ciok (MOV ol or)

    | _, _ =>
      cierror ii (Cerr_assembler
        (AsmErr_string "Invalid number of lval or pexpr in Ox86_MOV"))
    end

  | OK_MOVcc =>
    match as_singleton l, as_triple e with
    | Some l, Some (c, e1, e2) =>
      Let ol := oprd_of_lval ii l in
      Let or := oprd_of_pexpr ii e1 in 
      Let oc  := assemble_cond ii c in
      Let ol' := oprd_of_pexpr ii e2 in
      if   ol == ol'
      then ciok (CMOVcc oc ol or)
      else
        cierror ii (Cerr_assembler
          (AsmErr_string "lval & rval of Ox86_MOVcc should be the same"))

    | _, _ => 
      cierror ii (Cerr_assembler
        (AsmErr_string "Invalid number of lval or pexpr in Ox86_MOVcc"))
    end

  | OK_LEA => 
    match as_singleton l, as_quadruple e with
    | Some l, Some(d,b,sc,o) =>
      Let d := word_of_pexpr ii d in
      Let b := oreg_of_pexpr ii b in
      Let sc := word_of_pexpr ii sc in
      Let sc := scale_of_z ii (I64.unsigned sc) in
      Let o := oreg_of_pexpr ii o in
      Let l := oprd_of_lval ii l in
      ciok (LEA l (Adr_op (mkAddress d b sc o)))
    | _, _ =>   
      cierror ii (Cerr_assembler
        (AsmErr_string "Invalid number of lval or pexprs in Ox86_LEA"))
    end
  | OK_None =>
    cierror ii (Cerr_assembler
      (AsmErr_string (String.append "Unhandled sopn " (string_of_sopn o))))
  end.

(* -------------------------------------------------------------------- *)
Definition assemble_i (li: linstr) : ciexec asm :=
  let (ii, i) := li in
  match i with
  | Lassgn l _ e =>
     Let dst := oprd_of_lval ii l in
     Let src := oprd_of_pexpr ii e in
     ciok (MOV dst src)

  | Lopn l o p =>
      assemble_opn ii l o p

  | Llabel l =>
      ciok (LABEL l)

  | Lgoto l =>
      ciok (JMP l)

  | Lcond e l =>
      Let cond := assemble_cond ii e in
      ciok (Jcc l cond)
  end.

(* -------------------------------------------------------------------- *)
Definition assemble_c (lc: lcmd) : ciexec (seq asm) :=
  mapM assemble_i lc.

(* -------------------------------------------------------------------- *)
Definition assemble_fd (fd: lfundef) :=
  Let fd' := assemble_c (lfd_body fd) in

  match (reg_of_string (lfd_nstk fd)) with
  | Some sp =>
      Let arg := reg_of_vars xH (lfd_arg fd) in
      Let res := reg_of_vars xH (lfd_res fd) in
      ciok (XFundef (lfd_stk_size fd) sp arg fd' res)

  | None =>
      cierror xH (Cerr_assembler (AsmErr_string "Invalid stack pointer"))
  end.

(* -------------------------------------------------------------------- *)
Definition assemble_prog (p: lprog) : cfexec xprog :=
  map_cfprog assemble_fd p.
