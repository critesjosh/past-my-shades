use dep::std::ec::tecurve::affine::Point as Gaffine;
use dep::std;
use dep::utils;
use dep::bjj;

fn main(
    private_key: Field,
    yay_votes: u40,
    nay_votes: u40,
    encrypted_yay_1: pub Gaffine,
    encrypted_yay_2: pub Gaffine,
    encrypted_nay_1: pub Gaffine,
    encrypted_nay_2: pub Gaffine
) -> pub Field {
    utils::assert_correct_clear_balance(private_key, yay_votes, encrypted_yay_1, encrypted_yay_2);
    utils::assert_correct_clear_balance(private_key, nay_votes, encrypted_nay_1, encrypted_nay_2);

    // return 0 if nay wins, 1 if yay wins
    if (nay_votes > yay_votes) { 0 } else { 1 }
}

