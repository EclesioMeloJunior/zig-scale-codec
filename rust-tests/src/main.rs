use parity_scale_codec::{Decode, Encode};

#[derive(Decode, Encode)]
struct Animal<N> {
    name: String,
    age: N,
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
        let cow = Animal::<u64> {
            name: String::from("cow_name"),
            age: 10,
        };
        println!("{:?}", cow.encode());

        let tuple_cow = (String::from("cow_name"), 10_u64);
        println!("{:?}", tuple_cow.encode());
    }
}
