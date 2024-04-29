use parity_scale_codec::{Decode, Encode};

#[derive(Decode, Encode)]
struct Animal {
    name: String,
}

fn main() {
    println!("Hello, world!");
}

#[cfg(test)]
mod test {
    use parity_scale_codec::Encode;

    use crate::Animal;

    #[test]
    fn encoding_struct() {
        let cow = Animal {
            name: String::from("cow_name"),
        };

        let output = cow.encode();
        println!("{:?}", output);
    }
}
