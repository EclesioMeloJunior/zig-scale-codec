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
    use parity_scale_codec::{Compact, Encode};

    use crate::Animal;

    #[test]
    fn encoding_compact_u8() {
        let compact: Compact<u8> = Compact(0b0011_1111);
        println!("{:?}", compact.encode());
    }

    #[test]
    fn encoding_struct() {
        let cow = Animal {
            name: String::from("cow_name"),
        };

        let output = cow.encode();
        println!("{:?}", output);
    }
}
