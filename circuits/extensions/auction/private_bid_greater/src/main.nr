use dep::std::ec::tecurve::affine::Point as Gaffine;
use dep::std;
use dep::utils;
use dep::bjj;

fn main(
    private_key: Field,
    private_bid: u40,
    encrypted_bid: pub [Gaffine; 2],
    public_bid: pub Field
) -> pub Field {
    utils::assert_correct_clear_balance(private_key, private_bid, encrypted_bid[0], encrypted_bid[1]);
    if public_bid.lt(private_bid as Field) {
        1
    } else {
        0
    }
}
