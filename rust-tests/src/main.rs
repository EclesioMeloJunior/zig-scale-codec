fn main() {}

#[cfg(test)]
mod test {
    use parity_scale_codec::{Compact, Encode};

    #[test]
    fn encode_optional_bool() {
        let opt_bool: Option<bool> = Some(true);
        println!("{:?}", opt_bool.encode())
    }

    #[test]
    fn encoding_compact() {
        let compact: Compact<u128> = Compact(u128::MAX);
        println!("{:?}", compact.encode());
        println!("{:?}", compact.size_hint());
    }

    #[test]
    fn encoding_integers() {
        println!("{:?}", i64::MAX.encode());
    }

    #[test]
    fn encoding_struct() {
        #[derive(Encode)]
        struct Str<N, O> {
            str: String,
            number: N,
            opt: Option<O>,
        }

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

    #[test]
    fn encoding_result_type() {
        let a: Result<String, String> = Ok(String::from("eclesio"));
        println!("{:?}", a.encode());

        #[derive(Encode)]
        struct StrWithResult {
            result: Result<u64, String>,
            cmp: Compact<u64>,
        }

        let my_ok: StrWithResult = StrWithResult {
            result: Ok(100),
            cmp: Compact(u16::MAX as u64),
        };

        println!("{:?}", my_ok.encode());

        let my_ok: StrWithResult = StrWithResult {
            result: Err(String::from("fail")),
            cmp: Compact(u8::MAX as u64),
        };

        println!("{:?}", my_ok.encode());
    }

    #[test]
    fn encode_vectors() {
        let v1 = vec![Some(1), Some(2), Some(10000)];
        println!("{:?}", v1.encode());
        println!("{:?}", v1.size_hint());

        // let v2: Vec<u8> = vec![];
        // println!("{:?}", v2.encode());
        // println!("{:?}", v2.size_hint());
    }
}
