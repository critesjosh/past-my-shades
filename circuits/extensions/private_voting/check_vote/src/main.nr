use dep::std::ec::tecurve::affine::Point as Gaffine;
use dep::std;
use dep::utils;
use dep::bjj;
fn main(
    private_key: Field,
    recipient_pub_key: [u8; 32],
    yay_amount: u40,
    nay_amount: u40,
    balance: u40,
    randomness: Field,
    recipient_pub_key_modulus: pub Field,
    encrypted_balance_1: pub Gaffine,
    encrypted_balance_2: pub Gaffine,
    encrypted_yay_1: pub Gaffine,
    encrypted_yay_2: pub Gaffine,
    encrypted_nay_1: pub Gaffine,
    encrypted_nay_2: pub Gaffine
) {
    assert(recipient_pub_key_modulus == bjj::from_rpr_le(recipient_pub_key));

    utils::assert_correct_clear_balance(private_key, balance, encrypted_balance_1, encrypted_balance_2);
    // users can't vote more than their balance
    assert(yay_amount + nay_amount < balance, "vote amount must be less than balance");
    utils::assert_correct_recipient_balance(
        recipient_pub_key,
        yay_amount,
        randomness,
        encrypted_yay_1,
        encrypted_yay_2
    );
    utils::assert_correct_recipient_balance(
        recipient_pub_key,
        nay_amount,
        randomness,
        encrypted_nay_1,
        encrypted_nay_2
    );
}
