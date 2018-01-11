Require Import x86_sem compiler_util.
Import Utf8 String.
Import all_ssreflect.
Import xseq expr.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

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

Definition var_of_register r := 
  {| vtype := sword; vname := string_of_register r |}. 

Definition var_of_flag f := 
  {| vtype := sbool; vname := string_of_rflag f |}. 

Lemma var_of_register_inj x y :
  var_of_register x = var_of_register y →
  x = y.
Proof. by move=> [];apply inj_string_of_register. Qed.

Lemma var_of_flag_inj x y : 
  var_of_flag x = var_of_flag y →
  x = y.
Proof. by move=> [];apply inj_string_of_rflag. Qed.

Lemma var_of_register_var_of_flag r f :
  ¬ var_of_register r = var_of_flag f.
Proof. by case: r;case: f. Qed.

Definition register_of_var (v:var) : option register := 
  if v.(vtype) == sword then reg_of_string v.(vname)
  else None.

Lemma var_of_register_of_var v r :
  register_of_var v = Some r →
  var_of_register r = v.
Proof.
  rewrite /register_of_var /var_of_register;case:ifP => //.
  case: v => [vt vn] /= /eqP -> H;apply f_equal.
  by apply: inj_reg_of_string H; apply reg_of_stringK.
Qed.

Definition flag_of_var (v: var) : option rflag :=
  if v.(vtype) == sbool then rflag_of_string v.(vname)
  else None.

Lemma var_of_flag_of_var v f :
  flag_of_var v = Some f →
  var_of_flag f = v.
Proof.
  rewrite /flag_of_var /var_of_flag;case:ifP => //.
  case: v => [vt vn] /= /eqP -> H; apply f_equal.
  by apply: inj_rflag_of_string H; apply rflag_of_stringK.
Qed.

Definition compile_var (v: var) : option (register + rflag) :=
  match register_of_var v with
  | Some r => Some (inl r)
  | None =>
    match flag_of_var v with
    | Some f => Some (inr f)
    | None => None
    end
  end.

Lemma register_of_var_of_register r :
  register_of_var (var_of_register r) = Some r.
Proof.
  rewrite /register_of_var /var_of_register /=.
  by apply reg_of_stringK.
Qed.

(* -------------------------------------------------------------------- *)
(* Compilation of pexprs *)
(* -------------------------------------------------------------------- *)
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
Definition word_of_int (z: Z) := ciok (I64.repr z).

Definition reg_of_var ii (v: var) :=
  match v with
  | Var sword s =>
     match (reg_of_string s) with
     | Some r => ciok r
     | None => cierror ii (Cerr_assembler (invalid_register s))
     end
  | _ => cierror ii (Cerr_assembler (AsmErr_string "Invalid register type"))
  end.

Definition reg_of_vars ii (vs: seq var_i) :=
  mapM (reg_of_var ii \o v_var) vs.

(* -------------------------------------------------------------------- *)
Definition scale_of_z' ii z :=
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
  | Ofs_var   of var
  | Ofs_mul   of Z & var
  | Ofs_add   of Z & var & Z
  | Ofs_error.

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
    Let sc := scale_of_z' ii sc in
    ciok (mkAddress I64.zero (Some s) sc (Some x))
  | Ofs_add sc x z =>
    Let x := reg_of_var ii x in
    Let n := word_of_int z in
    Let sc := scale_of_z' ii sc in
    ciok (mkAddress n (Some s) sc (Some x))
  | Ofs_error =>
    cierror ii (Cerr_assembler (AsmErr_string "Invalid address expression"))
  end.

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

Lemma assemble_cond_eq_expr ii pe pe' c :
  eq_expr pe pe' →
  assemble_cond ii pe = ok c →
  assemble_cond ii pe = assemble_cond ii pe'.
Proof.
elim: pe pe' c => [ z | b | pe ih | x | g | x pe ih | x pe ih | op pe ih | op pe1 ih1 pe2 ih2 | pe1 ih1 pe2 ih2 pe3 ih3 ]
  [ z' | b' | pe' | x' | g' | x' pe' | x' pe' | op' pe' | op' pe1' pe2' | pe1' pe2' pe3' ] // c;
  try (move/eqP -> => //).
- by case: x x' => /= x _ [x' _] /eqP <-.
- case/andP => [/eqP] <- {op'} h; move: (h) => /ih {ih} ih.
  case: op => //.
  by case: pe h ih => //= x /=; case: pe' => // x' /eqP /= <- {x'}.
- case/andP => [] /andP [/eqP] <- {op'} h1 h2; rewrite -/eq_expr in h1, h2.
  move: (h1) => /ih1 {ih1} ih1; move: (h2) => /ih2 {ih2} ih2.
  case: op => //.
  + case: pe1 h1 ih1 => // - [] // - [] // [x xi]; case: pe1' => // - [] // - [] // [x' xi'] /eqP h.
    rewrite /= in h; subst x'.
    case: pe2 h2 ih2 => //.
    * case => // - [] // [y yi]; case: pe2' => // - [] // -[] // [y' yi'] /eqP h'.
      rewrite /= in h'; subst y'.
      by rewrite /=; case: (rflag_of_var _ _).
    case => // - [x1 xi1] - [] // - [x2  xi2] [] // [] // q.
    case: pe2' => // - [] // - [x1' xi1'] x2' q' /andP [/andP] [/eqP] /= -> {x1}.
    case: x2' => // x2' /eqP /= -> {x2}.
    case: q' => // - [] // q' /andP [_] h; rewrite -/eq_expr in h.
    case: q h => // y; case: q' => // y' h.
    case: (rflag_of_var _ x) => //=.
    case: (rflag_of_var _ x1') => //=.
    case: (rflag_of_var _ x2') => //=.
    case: (rflag_of_var _ y) => //=.
    move => oF oF' sF zF.
    case: (zF =P _) => //= -> {zF}.
    case: (sF =P _) => //= _ {sF}.
    case: (oF' =P _) => //= _ {oF'}.
    case: (oF =P _) => //= _ {oF}.
    move/(_ _ erefl).
    case: (rflag_of_var _ y') => //= oF'.
    by case: (oF' =P _).
  case: pe1 h1 ih1 => // - [x1 xi1]; case: pe1' => // x1' /eqP h1.
  rewrite /= in h1; subst x1.
  case: pe2 h2 ih2 => //.
  + case => x2 xi2; case: pe2' => // x2' /eqP h2.
    rewrite /= in h2; subst x2.
    rewrite /=.
    by case: (rflag_of_var _ x2').
  move => a1 a2 a3; case: pe2' => //.
  case: a1 => // -[x2 xi2] [] // x2' a2' a3' /andP [] /andP [/eqP] h.
  rewrite /= in h; subst x2.
  rewrite -/eq_expr.
  case: a2 => // - [] // - [] // -[z1 zi1].
  case: a2' => // - [] // - [] // z' /eqP h.
  rewrite /= in h; subst z1.
  case: a3 => // -[z2 zi2]; case: a3' => // z2' /eqP h.
  rewrite /= in h; subst z2.
  done.
case/andP => /andP []; rewrite -/eq_expr => h1 h2 h3.
move: (h1) => /ih1 {ih1} ih1.
move: (h2) => /ih2 {ih2} ih2.
move: (h3) => /ih3 {ih3} ih3.
case: pe1 h1 ih1 => // -[x1 xi1]; case: pe1' => // x1' /eqP h.
rewrite /= in h; subst x1.
case: pe2 h2 ih2 => //.
+ case => [x2 xi2]; case: pe2' => // x2' /eqP h.
  rewrite /= in h; subst x2.
  case: pe3 h3 ih3 => // - [] // - [] // - [x3 xi3].
  case: pe3' => // - [] // -[] // x3' /eqP h.
  rewrite /= in h; subst x3.
  done.
case => // - [] // - [x2 xi2].
case: pe2' => // -[] // -[] // x2' /eqP h.
rewrite /= in h; subst x2.
case: pe3 h3 ih3 => // -[x3 xi3].
case: pe3' => // x3' /eqP h.
rewrite /= in h; subst x3.
done.
Qed.

Lemma addr_ofs_eq_expr pe pe' :
  eq_expr pe pe' →
  addr_ofs pe = addr_ofs pe'.
Proof.
elim: pe pe' => [ z | b | pe ih | x | g | x pe ih | x pe ih | op pe ih | op pe1 ih1 pe2 ih2 | pe1 ih1 pe2 ih2 pe3 ih3 ]
  [ z' | b' | pe' | x' | g' | x' pe' | x' pe' | op' pe' | op' pe1' pe2' | pe1' pe2' pe3' ] //;
  try (move/eqP -> => //).
- move => h; move: (h) => /ih {ih} ih.
  by case: pe h ih => // z; case: pe' => // z' /eqP ->.
- by case: x => x xi /eqP /= ->.
case/andP => /andP [/eqP] <- {op'}; rewrite -/eq_expr => h1 h2.
move: (h1) => /ih1 {ih1} ih1.
move: (h2) => /ih2 {ih2} ih2.
by case: op => // - [] //; rewrite /= ih1 ih2.
Qed.

Lemma addr_of_pexpr_eq_expr ii r pe pe' a :
  eq_expr pe pe' →
  addr_of_pexpr ii r pe = ok a →
  addr_of_pexpr ii r pe = addr_of_pexpr ii r pe'.
Proof.
elim: pe pe' a => [ z | b | pe ih | x | g | x pe ih | x pe ih | op pe ih | op pe1 ih1 pe2 ih2 | pe1 ih1 pe2 ih2 pe3 ih3 ]
  [ z' | b' | pe' | x' | g' | x' pe' | x' pe' | op' pe' | op' pe1' pe2' | pe1' pe2' pe3' ] // c;
  try (move/eqP -> => //).
- move => h; move: (h) => /ih {ih} ih.
  by case: pe h ih => // z; case: pe' => // z' /eqP ->.
- by case: x => x xi /eqP /= ->.
case/andP => /andP [/eqP] <- {op'}; rewrite -/eq_expr => h1 h2.
by case: op => // - [] //;
rewrite /addr_of_pexpr /= (addr_ofs_eq_expr h1) (addr_ofs_eq_expr h2).
Qed.

Lemma oprd_of_pexpr_eq_expr ii pe pe' o :
  eq_expr pe pe' →
  oprd_of_pexpr ii pe = ok o →
  oprd_of_pexpr ii pe = oprd_of_pexpr ii pe'.
Proof.
elim: pe pe' o => [ z | b | pe ih | x | g | x pe ih | x pe ih | op pe ih | op pe1 ih1 pe2 ih2 | pe1 ih1 pe2 ih2 pe3 ih3 ]
  [ z' | b' | pe' | x' | g' | x' pe' | x' pe' | op' pe' | op' pe1' pe2' | pe1' pe2' pe3' ] // o;
  try (move/eqP -> => //).
- move => h; move: (h) => /ih {ih} ih.
  by case: pe h ih => // z; case: pe' => // z' /eqP ->.
- by case: x => x xi /eqP /= ->.
case/andP => /eqP hx h; rewrite -/eq_expr in h.
case: x hx => x xi /= -> {x}.
move: (h) => /ih {ih}.
case: (reg_of_var _ _) => //= r ih; t_xrbindP => a ha _.
by rewrite (addr_of_pexpr_eq_expr h ha).
Qed.
