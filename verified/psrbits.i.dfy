include "ARMdef.dfy"
include "bitvectors.i.dfy"

lemma lemma_update_psr'(oldpsr:word, newmode:word, f:bool, i:bool, newpsr:word)
    requires ValidPsrWord(oldpsr)
    requires ValidModeEncoding(newmode)
    requires newpsr == update_psr(oldpsr, newmode, f, i);
    ensures ValidPsrWord(newpsr)
    ensures decode_psr(newpsr).m == decode_mode(newmode)
{
    reveal_update_psr();

    var maskbits := BitOr(if f then 0x40 else 0, if i then 0x80 else 0);
    assert maskbits == (
        if f && i then 0xc0
        else if f then 0x40
        else if i then 0x80
        else 0) by { reveal_BitOr(); }

    assert BitsAsWord(0xffffffe0) == 0xffffffe0 && BitsAsWord(0x1f) == 0x1f
        by { reveal_BitsAsWord(); }
    assert WordAsBits(0x10) == 0x10 && WordAsBits(0x1b) == 0x1b
        by { reveal_WordAsBits(); }

    var newpsr := update_psr(oldpsr, newmode, f, i);
    var oldpsrb := WordAsBits(oldpsr);
    var newmodeb := WordAsBits(newmode);

    assert 0x10 <= newmodeb <= 0x1b
    by {
        assert 0x10 <= newmode <= 0x1b;
        lemma_BitCmpEquiv(0x10, newmode);
        lemma_BitCmpEquiv(0x1b, newmode);
    }

    assert newpsr == BitsAsWord(BitOr(BitAnd(oldpsrb, 0xffffffe0),
            BitOr(newmodeb, maskbits))) by { lemma_BitsAndWordConversions(); }

    calc {
        psr_mask_mode(newpsr);
        BitwiseAnd(newpsr, 0x1f);
        { lemma_BitsAndWordConversions(); }
        BitsAsWord(BitAnd(BitOr(BitAnd(oldpsrb, 0xffffffe0),
            BitOr(newmodeb, maskbits)), 0x1f));
        { reveal_BitAnd(); reveal_BitOr(); }
        BitsAsWord(newmodeb);
        { lemma_BitsAndWordConversions(); }
        newmode;
    }
}

lemma lemma_update_psr(oldpsr:word, newmode:word, f:bool, i:bool)
    requires ValidPsrWord(oldpsr)
    requires ValidModeEncoding(newmode)
    ensures ValidPsrWord(update_psr(oldpsr, newmode, f, i))
    ensures decode_psr(update_psr(oldpsr, newmode, f, i))
        == var o := decode_psr(oldpsr); PSR(decode_mode(newmode), f || o.f, i || o.i)
{
    reveal_update_psr();

    var maskbits := BitOr(if f then 0x40 else 0, if i then 0x80 else 0);
    assert maskbits == (
        if f && i then 0xc0
        else if f then 0x40
        else if i then 0x80
        else 0) by { reveal_BitOr(); }

    assert BitsAsWord(0xc0) == 0xc0 && BitsAsWord(0x40) == 0x40
        && BitsAsWord(0x80) == 0x80 && BitsAsWord(0xffffffe0) == 0xffffffe0
        && BitsAsWord(0x1f) == 0x1f
        by { reveal_BitsAsWord(); }
    assert WordAsBits(0x10) == 0x10 && WordAsBits(0x1b) == 0x1b
        by { reveal_WordAsBits(); }

    var newpsr := update_psr(oldpsr, newmode, f, i);
    var oldpsrb := WordAsBits(oldpsr);
    var newmodeb := WordAsBits(newmode);

    assert 0x10 <= newmodeb <= 0x1b
    by {
        assert 0x10 <= newmode <= 0x1b;
        lemma_BitCmpEquiv(0x10, newmode);
        lemma_BitCmpEquiv(0x1b, newmode);
    }

    assert newpsr == BitsAsWord(BitOr(BitAnd(oldpsrb, 0xffffffe0),
            BitOr(newmodeb, maskbits))) by { lemma_BitsAndWordConversions(); }

    lemma_update_psr'(oldpsr, newmode, f, i, newpsr);

    calc {
        decode_psr(newpsr).f;
        BitwiseAnd(newpsr, 0x40) != 0;
        { lemma_BitsAndWordConversions(); }
        BitsAsWord(BitAnd(BitOr(BitAnd(oldpsrb, 0xffffffe0),
            BitOr(newmodeb, maskbits)), 0x40)) != 0;
        { calc {
            BitAnd(BitOr(BitAnd(oldpsrb, 0xffffffe0),
                BitOr(newmodeb, maskbits)), 0x40);
            { reveal_BitAnd(); reveal_BitOr(); }
            BitAnd(BitOr(oldpsrb, maskbits), 0x40);
        } }
        BitsAsWord(BitAnd(BitOr(oldpsrb, maskbits), 0x40)) != 0;
        {
            calc {
                decode_psr(oldpsr).f;
                BitwiseAnd(oldpsr, 0x40) != 0;
                { lemma_BitsAndWordConversions(); }
                BitAnd(oldpsrb, 0x40) != 0;
            }

            assert (BitAnd(maskbits, 0x40) != 0) == f by { reveal_BitAnd(); }

            reveal_BitAnd(); reveal_BitOr();
        }
        f || decode_psr(oldpsr).f;
    }

    calc {
        decode_psr(newpsr).i;
        BitwiseAnd(newpsr, 0x80) != 0;
        { lemma_BitsAndWordConversions(); }
        BitsAsWord(BitAnd(BitOr(BitAnd(oldpsrb, 0xffffffe0),
            BitOr(newmodeb, maskbits)), 0x80)) != 0;
        { calc {
            BitAnd(BitOr(BitAnd(oldpsrb, 0xffffffe0),
                BitOr(newmodeb, maskbits)), 0x80);
            { reveal_BitAnd(); reveal_BitOr(); }
            BitAnd(BitOr(oldpsrb, maskbits), 0x80);
        } }
        BitsAsWord(BitAnd(BitOr(oldpsrb, maskbits), 0x80)) != 0;
        {
            calc {
                decode_psr(oldpsr).i;
                BitwiseAnd(oldpsr, 0x80) != 0;
                { lemma_BitsAndWordConversions(); }
                BitAnd(oldpsrb, 0x80) != 0;
            }

            assert (BitAnd(maskbits, 0x80) != 0) == i by { reveal_BitAnd(); }

            reveal_BitAnd(); reveal_BitOr();
        }
        i || decode_psr(oldpsr).i;
    }
}
