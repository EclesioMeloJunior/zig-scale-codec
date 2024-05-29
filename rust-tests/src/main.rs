use parity_scale_codec::{Decode, Encode};

#[derive(Decode, Encode)]
struct Str<N, O> {
    str: String,
    number: N,
    opt: Option<O>,
}

fn main() {
    println!("Hello, world!");
}

#[cfg(test)]
mod test {
    use parity_scale_codec::{Compact, Encode};

    use crate::Str;

    #[test]
    fn encode_optional_bool() {
        let opt_bool: Option<bool> = Some(true);
        println!("{:?}", opt_bool.encode())
    }

    #[test]
    fn encoding_compact_u8() {
        let compact: Compact<u64> = Compact(10);
        println!("{:?}", compact.encode());
    }

    #[test]
    fn encoding_integers() {
        println!("{:?}", i64::MAX.encode());
    }

    #[test]
    fn encoding_struct() {
        let vars = vec![
            Str::<u64, bool> {
                str: String::from("some_name"),
                number: 10,
                opt: Some(true),
            },
            Str::<u64, bool> {
                str: String::from("some_name"),
                number: 10,
                opt: Some(false),
            },
            Str::<u64, bool> {
                str: String::from("some_name"),
                number: 10,
                opt: None,
            },
        ];

        for v in vars {
            println!("{:?}", v.encode());
        }
    }
}
