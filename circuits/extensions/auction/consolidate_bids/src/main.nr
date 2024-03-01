use dep::std::ec::tecurve::affine::Point as Gaffine;
use dep::std;
use dep::utils;
use dep::bjj;

fn main(
    private_key: Field,
    bids: [u40; 2],
    bid_1_pub: pub [Gaffine; 2],
    bid_2_pub: pub [Gaffine; 2],
    bid_3_pub: pub [Gaffine; 2],
    bid_4_pub: pub [Gaffine; 2]
) -> pub u40 {
    utils::assert_correct_clear_balance(private_key, bids[0], bid_1_pub[0], bid_1_pub[1]);
    utils::assert_correct_clear_balance(private_key, bids[1], bid_2_pub[0], bid_2_pub[1]);
    utils::assert_correct_clear_balance(private_key, bids[1], bid_3_pub[0], bid_3_pub[1]);
    utils::assert_correct_clear_balance(private_key, bids[1], bid_4_pub[0], bid_4_pub[1]);

    // return the index of the highest bid
    if (bids[0] > bids[1] & bids[0] > bids[2] & bids[0] > bids[3]) {
        0
    } else if (bids[1] > bids[0] & bids[1] > bids[2] & bids[1] > bids[3]) {
        1
    } else if (bids[2] > bids[0] & bids[2] > bids[1] & bids[2] > bids[3]) {
        2
    } else {
        3
    }
}

