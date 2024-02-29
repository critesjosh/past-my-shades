use dep::std::ec::tecurve::affine::Point as Gaffine;
use dep::std::ec::tecurve::affine::Curve as AffineCurve;
use dep::std;
use dep::utils;
use dep::bjj;

// dont need to check that the amount_to_add is correctly encrypted in this circuit (specifically for the private fundraising) 
// because it is checked as part of the transfer circuit in the same function
fn main(
    starting_value_1: pub Gaffine,
    starting_value_2: pub Gaffine,
    amount_to_add_1: pub Gaffine,
    amount_to_add_2: pub Gaffine,
    final_value_1: pub Gaffine,
    final_value_2: pub Gaffine
) {
    let bjj_affine = bjj::get_affine_curve();
    let final_value_computed = (
        bjj_affine.add(amount_to_add_1, starting_value_1), bjj_affine.add(starting_value_2, amount_to_add_2)
    );
    assert(final_value_computed.0.x == final_value_1.x);
    assert(final_value_computed.0.y == final_value_1.y);
    assert(final_value_computed.1.x == final_value_2.x);
    assert(final_value_computed.1.y == final_value_2.y);
}

// #[test]
// fn test_main() {

//     // Uncomment to make test fail
//     // main(1, 1);
// }
